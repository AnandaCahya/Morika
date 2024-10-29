#!/bin/bash

# Memastikan skrip dijalankan dengan hak akses root
if [ "$(id -u)" -ne 0 ]; then
  echo "Silakan jalankan skrip ini sebagai root atau dengan sudo."
  exit 1
fi

# Mendapatkan nama pengguna yang menjalankan skrip
USERNAME=$(logname)

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
  lightdm \
  openbox \
  xorg \
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

# Menambahkan repositori dan menginstal Teleport
VERSION=$(curl -s https://api.github.com/repos/gravitational/teleport/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
wget "https://get.gravitational.com/teleport_${VERSION}_amd64.deb"
apt install -y ./teleport_${VERSION}_amd64.deb
rm -f ./teleport_${VERSION}_amd64.deb
echo "Teleport telah diinstal dari paket."

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

# Deteksi interface aktif
INTERFACE=$(ip -o -f inet addr show | awk '{print $2}' | head -n 1)
if [ -z "$INTERFACE" ]; then
  echo "Tidak ada interface jaringan yang ditemukan."
  exit 1
fi

echo "Menggunakan interface: $INTERFACE"

# Backup file konfigurasi Snort
cp /etc/snort/snort.conf /etc/snort/snort.conf.bak

# Konfigurasi HOME_NET dan EXTERNAL_NET
sed -i "s/^var HOME_NET.*/var HOME_NET [192.168.1.0\/24]/" /etc/snort/snort.conf
sed -i "s/^var EXTERNAL_NET.*/var EXTERNAL_NET any/" /etc/snort/snort.conf

# Konfigurasi logging
sed -i "s/^output unified2:.*/output unified2: filename \/var\/log\/snort\/snort.log, limit 128/" /etc/snort/snort.conf

# Tambahkan rules dasar jika local.rules tidak ada
if [ ! -f /etc/snort/rules/local.rules ]; then
  echo "# Rules tambahan" > /etc/snort/rules/local.rules
fi

# Tambahkan contoh rules jika belum ada
if ! grep -q "ICMP Packet Detected" /etc/snort/rules/local.rules; then
  echo "alert icmp any any -> \$HOME_NET any (msg:\"ICMP Packet Detected\"; sid:1000001;)" >> /etc/snort/rules/local.rules
fi

if ! grep -q "HTTP Packet Detected" /etc/snort/rules/local.rules; then
  echo "alert tcp any any -> \$HOME_NET 80 (msg:\"HTTP Packet Detected\"; sid:1000002;)" >> /etc/snort/rules/local.rules
fi

# Cek konfigurasi Snort
snort -T -c /etc/snort/snort.conf
if [ $? -ne 0 ]; then
  echo "Konfigurasi Snort tidak valid. Silakan periksa error di atas."
  exit 1
fi

# Jalankan Snort
snort -A console -c /etc/snort/snort.conf -i "$INTERFACE" &

echo "Snort sudah dijalankan di interface $INTERFACE"

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

# Mengonfigurasi login otomatis
echo "Mengonfigurasi login otomatis..."
cat <<EOF >> /etc/lightdm/lightdm.conf
[Seat:*]
autologin-user=$USERNAME
EOF

# Menambahkan skrip untuk membuka Chromium
echo "Menambahkan skrip untuk membuka Chromium..."
cat <<EOF > /home/$USERNAME/start_chromium.sh
#!/bin/bash
sleep 5  # Menunggu beberapa detik agar desktop sepenuhnya siap
chromium --new-window "http://localhost:3080" "http://localhost:443"
EOF

chmod +x /home/$USERNAME/start_chromium.sh

# Menambahkan perintah ke .xprofile untuk menjalankan skrip saat login
echo "/home/$USERNAME/start_chromium.sh &" >> /home/$USERNAME/.xprofile

echo "Instalasi selesai! Server Anda sekarang siap digunakan."
echo "Akses web UI Teleport di http://$SERVER_IP:3080"
echo "Akses web UI Security Onion di http://$SERVER_IP:443"

# Reboot sistem
echo "Rebooting sistem dalam 5 detik..."
sleep 5
reboot
