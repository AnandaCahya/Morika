#!/bin/bash

# Memastikan skrip dijalankan dengan hak akses root
if [ "$(id -u)" -ne 0 ]; then
  echo "Silakan jalankan skrip ini sebagai root atau dengan sudo."
  exit 1
fi

# Memperbarui sistem
echo "Memperbarui sistem..."
apt update && apt upgrade -y

# Menginstal aplikasi dasar
echo "Menginstal aplikasi dasar..."
apt install -y \
  git \
  curl \
  vim \
  htop \
  ufw \
  software-properties-common \
  policycoreutils \
  selinux-utils \
  selinux-basics \
  kubelet \
  kubeadm \
  kubectl \
  virt-manager \
  qemu-kvm \
  libvirt-daemon-system \
  libvirt-clients \
  wget \
  xvfb \
  chromium

# Mengonfigurasi SELinux
echo "Mengonfigurasi SELinux..."
selinux-basics --enable
setenforce 1
echo "SELinux diatur ke enforcing."

# Mengonfigurasi firewall
echo "Mengonfigurasi firewall..."
ufw allow OpenSSH
ufw allow 3022  # Port default untuk SSH
ufw allow 6443  # Port untuk Kubernetes API server
ufw allow 3080  # Port untuk Teleport
ufw allow 3081  # Port untuk proxy Teleport
ufw allow 443   # Port untuk Security Onion Web UI
ufw enable
ufw status

# Menginstal Nginx
echo "Menginstal Nginx..."
apt install -y nginx

# Mengaktifkan dan memulai Nginx
systemctl enable nginx
systemctl start nginx

#!/bin/bash

# Menghapus repositori yang tidak dapat diakses
SOURCE_FILE="/etc/apt/sources.list.d/teleport.list"

if [ -f "$SOURCE_FILE" ]; then
  echo "Menghapus repositori yang tidak dapat diakses: $SOURCE_FILE"
  rm -f "$SOURCE_FILE"
  echo "Repositori telah dihapus."
fi

# Menambahkan repositori dan menginstal Teleport
echo "Menambahkan repositori Teleport..."
if wget -q --spider https://deb.gravitational.io/; then
  echo "Repositori Teleport dapat diakses."
  echo "Menambahkan repositori..."
  wget -qO - https://deb.gravitational.io/GRAVITATIONAL-GPG.key | apt-key add -
  echo "deb https://deb.gravitational.io/ teleport main" | tee /etc/apt/sources.list.d/teleport.list
else
  echo "Repositori tidak dapat diakses. Mengunduh paket secara manual."
  VERSION=$(curl -s https://api.github.com/repos/gravitational/teleport/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
  wget "https://get.gravitational.com/teleport_${VERSION}_amd64.deb"
  apt install -y ./teleport_${VERSION}_amd64.deb
  rm -f ./teleport_${VERSION}_amd64.deb
  echo "Teleport telah diinstal dari paket."
  exit 0
fi

# Memperbarui daftar paket
echo "Memperbarui daftar paket..."
apt update

# Menginstal Teleport
echo "Menginstal Teleport..."
apt install -y teleport

echo "Instalasi Teleport selesai!"

# Mendapatkan alamat IP server
SERVER_IP=$(hostname -I | awk '{print $1}')

# Mengonfigurasi Teleport
echo "Mengonfigurasi Teleport..."
cat <<EOF > /etc/teleport.yaml
teleport:
  nodename: "$HOSTNAME"
  data_dir: "/var/lib/teleport"
  auth_servers:
    - "localhost:3025"
  log:
    output: "stdout"
    severity: "INFO"
  service:
    enabled: yes
    type: auth

auth_service:
  enabled: yes

ssh_service:
  enabled: yes

web_service:
  enabled: yes

kubernetes:
  enabled: yes
  listen_addr: 0.0.0.0:3080
  public_addr: "$SERVER_IP:3080"

proxy_service:
  enabled: yes
  listening_addr: "0.0.0.0:3081"
EOF

# Mengaktifkan dan memulai layanan Teleport
systemctl enable teleport
systemctl start teleport

# Menginstal Security Onion
echo "Menginstal Security Onion..."
apt install -y securityonion

# Menjalankan konfigurasi Security Onion
echo "Menjalankan konfigurasi Security Onion..."
so-setup

# Menginstal ClamAV
echo "Menginstal ClamAV..."
apt install -y clamav clamav-daemon
freshclam  # Memperbarui database ClamAV

# Menginstal Fail2Ban
echo "Menginstal Fail2Ban..."
apt install -y fail2ban
cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime  = 1h
findtime = 1h
maxretry = 3

[sshd]
enabled = true
port = 3022  # Ubah port SSH
EOF

# Mengaktifkan dan memulai Fail2Ban
systemctl enable fail2ban
systemctl start fail2ban

# Menginstal Suricata
echo "Menginstal Suricata..."
apt install -y suricata
suricata-update

# Mengaktifkan Suricata
systemctl enable suricata
systemctl start suricata

# Menginstal ModSecurity
echo "Menginstal ModSecurity..."
apt install -y libapache2-mod-security2
cp /etc/modsecurity/modsecurity.conf-recommended /etc/modsecurity/modsecurity.conf
sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' /etc/modsecurity/modsecurity.conf

# Menginstal dan mengaktifkan Apache
echo "Menginstal dan mengaktifkan Apache..."
apt install -y apache2
systemctl enable apache2
systemctl start apache2

# Menginstal DDoS Deflate
echo "Menginstal DDoS Deflate..."
git clone https://github.com/jgmize/ddos-deflate.git /usr/local/ddos
cd /usr/local/ddos
bash install.sh

# Menginstal RKHunter dan Chkrootkit
echo "Menginstal RKHunter dan Chkrootkit..."
apt install -y rkhunter chkrootkit

# Mengonfigurasi RKHunter
echo "Mengonfigurasi RKHunter..."
echo "ALLOW_HIDDEN=1" >> /etc/rkhunter.conf
rkhunter --update
rkhunter --propupdate

# Menambahkan cron job untuk RKHunter dan Chkrootkit
echo "Menambahkan cron job untuk RKHunter dan Chkrootkit..."
(crontab -l 2>/dev/null; echo "0 2 * * * /usr/bin/rkhunter --check") | crontab -
(crontab -l 2>/dev/null; echo "0 3 * * * /sbin/chkrootkit") | crontab -

# Menginstal Prometheus Node Exporter
echo "Menginstal Prometheus Node Exporter..."
wget https://github.com/prometheus/node_exporter/releases/latest/download/node_exporter-*.tar.gz
tar -xvf node_exporter-*.tar.gz
mv node_exporter-* node_exporter
mv node_exporter/node_exporter /usr/local/bin/

# Mengatur layanan Node Exporter
cat <<EOF > /etc/systemd/system/node_exporter.service
[Unit]
Description=Prometheus Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=root
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

# Mengaktifkan dan memulai Node Exporter
systemctl enable node_exporter
systemctl start node_exporter

# Mengubah port SSH
echo "Mengubah port SSH..."
sed -i 's/#Port 22/Port 3022/' /etc/ssh/sshd_config
systemctl restart ssh

# Nonaktifkan root login
echo "Menonaktifkan login root melalui SSH..."
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart ssh

# Menginstal AppArmor
echo "Menginstal dan mengaktifkan AppArmor..."
apt install -y apparmor apparmor-utils
systemctl enable apparmor
systemctl start apparmor

# Menginstal Snort
echo "Menginstal Snort..."
apt install -y snort

# Mengonfigurasi Snort
echo "Mengonfigurasi Snort..."
cat <<EOF > /etc/snort/snort.conf
var HOME_NET any
var EXTERNAL_NET any
include \$SNORT_HOME/rules/local.rules
output unified2: filename snort.log, limit 128
EOF

# Mengaktifkan dan memulai Snort
systemctl enable snort
systemctl start snort

# Menginstal AIDE
echo "Menginstal AIDE..."
apt install -y aide

# Mengonfigurasi AIDE
echo "Mengonfigurasi AIDE..."
aideinit  # Inisialisasi basis data AIDE
mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db  # Pindahkan basis data yang baru dibuat

# Menambahkan cron job untuk AIDE
echo "Menambahkan cron job untuk AIDE..."
(crontab -l 2>/dev/null; echo "0 1 * * * /usr/bin/aide --check") | crontab -

# Membuat skrip auto start untuk membuka antarmuka web
AUTO_START_SCRIPT="/usr/local/bin/open_web_ui.sh"
cat <<EOF > $AUTO_START_SCRIPT
#!/bin/bash
DISPLAY=:99
Xvfb :99 -screen 0 1024x768x16 &
sleep 2
chromium --no-sandbox --disable-dev-shm-usage "http://$SERVER_IP:3080" &
chromium --no-sandbox --disable-dev-shm-usage "http://$SERVER_IP:443" &
EOF

chmod +x $AUTO_START_SCRIPT

# Menambahkan ke cron job untuk menjalankan skrip auto start saat boot
(crontab -l 2>/dev/null; echo "@reboot $AUTO_START_SCRIPT") | crontab -

echo "Instalasi selesai! Server Anda sekarang siap digunakan."
echo "Akses web UI Teleport di http://$SERVER_IP:3080"
echo "Akses web UI Security Onion di http://$SERVER_IP:443"
