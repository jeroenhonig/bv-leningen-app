#!/bin/bash
# Instructies om het script aan je Git repository toe te voegen

# Ga naar de directory van je lokale Git repository
cd /pad/naar/je/bv-leningen-app

# Maak een directory voor Proxmox installatie als deze nog niet bestaat
mkdir -p install/proxmox

# Maak het script
cat > install/proxmox/create-lxc.sh << 'EOF'
#!/bin/bash
# Eenvoudig script voor BV Leningen App installatie
# Gebruik: sla dit op als install-leningen-app.sh, maak het uitvoerbaar (chmod +x install-leningen-app.sh), en voer het uit (./install-leningen-app.sh)

set -e

# Bepaal container ID (gebruik 105 als standaard, of pas dit aan)
CTID=105
HOSTNAME="leningen-app"
MEM=2048
CORES=2
DISK=8
PASSWORD=$(openssl rand -base64 12)

echo "BV Leningen App installatie"
echo "Container ID: $CTID"
echo "Hostname: $HOSTNAME"
echo "Geheugen: $MEM MB"
echo "CPU cores: $CORES"
echo "Schijfruimte: $DISK GB"

# Download Debian template
TEMPLATE=$(pveam available | grep -o 'debian-12-standard[^ ]*\.tar\.\(gz\|xz\|zst\)' | sort -V | tail -n1)
pveam download local "$TEMPLATE"

# Container aanmaken
pct create $CTID "local:vztmpl/$TEMPLATE" \
  --hostname $HOSTNAME \
  --memory $MEM \
  --cores $CORES \
  --rootfs local-lvm:$DISK \
  --password "$PASSWORD" \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --unprivileged 1 \
  --features nesting=1

# Container starten
pct start $CTID
sleep 10  # Wacht tot de container is opgestart

# Het setup script aanmaken en naar de container kopiëren
cat > setup.sh << 'EOF'
#!/bin/bash
# BV Leningen App setup script

set -e

# Configuratie
APP_DIR="/opt/leningen-app"
DB_USER="leningen_user"
DB_PASS="leningen_pass"
DB_NAME="leningen_db"

echo "=== BV Leningen App installatie ==="

# 1. Locale problemen oplossen
echo "1. Locales instellen..."
apt-get update
apt-get install -y locales
sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# 2. Systeem updaten
echo "2. Systeem bijwerken..."
apt-get update
apt-get upgrade -y

# 3. Benodigde software installeren
echo "3. Software installeren..."
apt-get install -y curl gnupg git ca-certificates

# 4. Node.js installeren
echo "4. Node.js installeren..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# 5. PostgreSQL installeren
echo "5. PostgreSQL installeren..."
apt-get install -y postgresql postgresql-contrib
pg_ctlcluster 15 main start || true

# 6. Nginx installeren
echo "6. Nginx installeren..."
apt-get install -y nginx
systemctl enable --now nginx

# 7. Repository klonen
echo "7. Repository klonen..."
mkdir -p "$APP_DIR"
cd "$APP_DIR"
git clone https://github.com/jeroenhonig/bv-leningen-app.git repo

# 8. Database configureren
echo "8. Database configureren..."
su - postgres -c "psql -v ON_ERROR_STOP=1 -c \"CREATE ROLE \${DB_USER} WITH LOGIN PASSWORD '\${DB_PASS}';\" || true"
su - postgres -c "psql -v ON_ERROR_STOP=1 -c \"CREATE DATABASE \${DB_NAME} OWNER \${DB_USER};\" || true"
su - postgres -c "psql -d \${DB_NAME} -tAc \"SELECT 1 FROM information_schema.tables WHERE table_name = 'lening'\"" | grep -q 1 || \
su - postgres -c "psql -d \${DB_NAME} -f \${APP_DIR}/repo/database/schema.sql"

# 9. Backend dependencies installeren
echo "9. Backend dependencies installeren..."
cd "$APP_DIR/repo/backend"
npm ci --omit=dev

# 10. Frontend bouwen
echo "10. Frontend bouwen..."
cd "$APP_DIR/repo/frontend"
npm ci
npm run build

# 11. Nginx configureren
echo "11. Nginx configureren..."
rm -rf /var/www/html/*
cp -r "$APP_DIR/repo/frontend/build"/* /var/www/html/

# Reverse proxy configureren
cat > /etc/nginx/conf.d/leningen-app.conf << 'NGINX_CONF'
server {
    listen 80;
    server_name _;
    
    root /var/www/html;
    try_files \$uri /index.html;
    
    location /api/ {
        proxy_pass http://127.0.0.1:3000/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
NGINX_CONF

nginx -t && systemctl reload nginx

# 12. PM2 installeren en backend starten
echo "12. PM2 installeren..."
npm install -g pm2
pm2 startup systemd -u root --hp /root --silent

cd "$APP_DIR/repo/backend"
if [ -f index.js ]; then
  pm2 start index.js --name leningen-backend
elif [ -f server.js ]; then
  pm2 start server.js --name leningen-backend
else
  pm2 start npm --name leningen-backend -- run start
fi
pm2 save

# 13. Console autologin configureren
echo "13. Console autologin configureren..."
mkdir -p /etc/systemd/system/getty@tty1.service.d/
cat > /etc/systemd/system/getty@tty1.service.d/override.conf << 'EOT'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM
EOT
systemctl daemon-reload

echo "=== Installatie voltooid! ==="
IP=\$(hostname -I | awk '{print \$1}')
echo "Web interface beschikbaar op: http://\$IP"
echo "Database gebruiker: \$DB_USER"
echo "Database wachtwoord: \$DB_PASS"
echo "Database naam: \$DB_NAME"
EOF

# Setup script naar container kopiëren en uitvoeren
pct push $CTID setup.sh /root/setup.sh
pct exec $CTID -- chmod +x /root/setup.sh
pct exec $CTID -- bash /root/setup.sh

# Toon resultaat
IP=$(pct exec $CTID -- hostname -I | tr -d '\r\n')
echo "==============================================="
echo "BV Leningen App installatie voltooid!"
echo "Container ID: $CTID"
echo "Root wachtwoord: $PASSWORD"
echo "Web interface: http://$IP"
echo "==============================================="
EOF

# Maak het script uitvoerbaar
chmod +x install/proxmox/create-lxc.sh

# Voeg de wijzigingen toe aan Git
git add install/proxmox/create-lxc.sh

# Commit de wijzigingen met een beschrijvende commit message
git commit -m "Add fixed Proxmox LXC container installation script"

# Push de wijzigingen naar de remote repository (bijv. GitHub)
git push