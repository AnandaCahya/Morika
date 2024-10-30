#!/bin/bash

echo "Morika Installer (v1.0.0-test)"

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
  kubelet \
  kubeadm \
  kubectl \
  virt-manager \
  qemu-kvm \
  libvirt-daemon-system \
  libvirt-clients \
  wget \
  sddm \
  openbox \
  xorg \
  chromium-browser \
  clamav clamav-daemon \
  fail2ban \
  rkhunter chkrootkit \
  suricata \
  libapache2-mod-security2 \
  apache2 \
  aide

# Menginstal Security Onion
echo "Menginstal Security Onion..."
# Pastikan Anda menyesuaikan langkah ini sesuai dengan dokumentasi terbaru dari Security Onion.
wget -qO - https://securityonion.net/gpg.key | sudo apt-key add -
echo "deb https://securityonion.net/securityonion/ubuntu focal main" | sudo tee /etc/apt/sources.list.d/securityonion.list
apt update
apt install -y securityonion

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

# Menginstal Teleport
echo "Menginstal Teleport..."
VERSION=$(curl -s https://api.github.com/repos/gravitational/teleport/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
wget "https://get.gravitational.com/teleport_${VERSION}_amd64.deb"
dpkg -i "teleport_${VERSION}_amd64.deb" || apt -f install -y
rm -f "teleport_${VERSION}_amd64.deb"
echo "Teleport telah diinstal dari paket."

# Memperbarui daftar paket
echo "Memperbarui daftar paket..."
apt update

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

# Mengonfigurasi RKHunter
echo "Mengonfigurasi RKHunter..."
echo "ALLOW_HIDDEN=1" >> /etc/rkhunter.conf
rkhunter --update
rkhunter --propupdate

# Menambahkan cron job untuk RKHunter dan Chkrootkit
(crontab -l 2>/dev/null; echo "0 2 * * * /usr/bin/rkhunter --check") | crontab -
(crontab -l 2>/dev/null; echo "0 3 * * * /sbin/chkrootkit") | crontab -

# Mengonfigurasi login otomatis untuk SDDM
echo "Mengonfigurasi login otomatis untuk SDDM..."
cat <<EOF > /etc/sddm.conf
[Autologin]
User=$USERNAME
Session=openbox.desktop
EOF

# Membuat file konfigurasi Openbox
mkdir -p /home/$USERNAME/.config/openbox
cat <<EOF > /home/$USERNAME/.config/openbox/autostart
#!/bin/sh
chromium-browser --new-window "http://localhost:3080" "http://localhost:443" &
EOF

chmod +x /home/$USERNAME/.config/openbox/autostart

# Membuat file .xsession
echo "exec openbox-session" > /home/$USERNAME/.xsession

# Menyeting hak akses untuk pengguna
chown -R $USERNAME:$USERNAME /home/$USERNAME/.config

# Mengaktifkan dan memulai SDDM
systemctl enable sddm
systemctl start sddm

# Reboot sistem
echo "Rebooting sistem dalam 5 detik..."
sleep 5
reboot