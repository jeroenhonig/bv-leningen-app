#!/bin/bash
# Gerepareerde versie van het BV Leningen App installatiescript
# Deze versie vermijdt alle problemen met het originele script

set -e  # Stop bij fouten

# Functie om een vrij container ID te vinden
get_next_ctid() {
  used_ids=$(pvesh get /cluster/resources --type vm --output-format json | jq -r '.[] | select(.vmid) | .vmid')
  for id in $(seq 100 999); do
    echo "$used_ids" | grep -qw "$id" || { echo "$id"; return; }
  done
}

# Configuratie
CTID=$(get_next_ctid)
HOSTNAME="leningen-app"
INITIAL_MEM=2048
FINAL_MEM=512
INITIAL_CORES=4
FINAL_CORES=1
DISK=8
PASSWORD=$(openssl rand -base64 12)
IP_CONFIG="dhcp"
BRIDGE="vmbr0"

# Zoek de laatste debian-12-standard template
TEMPLATE_FILE=$(pveam available | grep -o 'debian-12-standard[^ ]*\.tar\.\(gz\|xz\|zst\)' | sort -V | tail -n1)
pveam download local "$TEMPLATE_FILE"
TEMPLATE_PATH="local:vztmpl/$TEMPLATE_FILE"

echo "BV Leningen App installatie starten..."
echo "Gekozen Container ID: $CTID"
echo "Hostname: $HOSTNAME"
echo "Tijdelijk geheugen: $INITIAL_MEM MB (later $FINAL_MEM MB)"
echo "Tijdelijk CPU cores: $INITIAL_CORES (later $FINAL_CORES)"
echo "Schijfruimte: $DISK GB"
echo "IP-configuratie: $IP_CONFIG"
echo "Netwerk bridge: $BRIDGE"
echo "Debian template: $TEMPLATE_PATH"

# Container aanmaken (zonder --lock parameter)
pct create $CTID $TEMPLATE_PATH \
  --hostname $HOSTNAME \
  --memory $INITIAL_MEM \
  --swap 512 \
  --cores $INITIAL_CORES \
  --rootfs local-lvm:$DISK \
  --password "$PASSWORD" \
  --net0 name=eth0,bridge=$BRIDGE,ip=$IP_CONFIG \
  --unprivileged 1 \
  --features nesting=1

echo "Container starten..."
pct start $CTID
echo "Wachten tot container is opgestart..."
sleep 10

# Maak een betrouwbaar setup script dat binnen de container zal draaien
echo "Setup script aanmaken..."
cat > setup-in-container.sh << 'EOL'
#!/bin/bash
# Setup script voor BV Leningen App

set -e

# Basis configuratie
APP_DIR="/opt/leningen-app"
DB_USER="leningen_user"
DB_PASS="leningen_pass"
DB_NAME="leningen_db"

echo "=== BV Leningen App installatie ==="

# 1. Fix locale issues
echo "1. Locales instellen..."
apt-get update
apt-get install -y locales
sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# 2. System updates
echo "2. Systeem bijwerken..."
apt-get update
apt-get upgrade -y

# 3. PostgreSQL installeren
echo "3. PostgreSQL installeren..."
apt-get install -y postgresql postgresql-contrib
if ! pg_lsclusters | grep -q "^15[[:space:]]\+main"; then
  echo "Geen 15/main cluster gevonden, initialiseren..."
  pg_createcluster 15 main --start
fi
pg_ctlcluster 15 main start || true

# 4. Node.js installeren
echo "4. Node.js installeren..."
apt-get install -y curl gnupg ca-certificates
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# 5. Webserver en Git installeren
echo "5. Webserver en Git installeren..."
apt-get install -y nginx git
systemctl enable --now nginx

# 6. Repository klonen
echo "6. Repository klonen..."
mkdir -p "$APP_DIR"
cd "$APP_DIR"
git clone https://github.com/jeroenhonig/bv-leningen-app.git repo

# 7. Database configureren
echo "7. Database configureren..."
# 7a. Role aanmaken
su - postgres -c "psql -v ON_ERROR_STOP=1 -c \"CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASS}';\" || true"

# 7b. Database aanmaken
su - postgres -c "psql -v ON_ERROR_STOP=1 -c \"CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};\" || true"

# 7c. Schema importeren
su - postgres -c "psql -d ${DB_NAME} -tAc \"SELECT 1 FROM information_schema.tables WHERE table_name = 'lening'\"" | grep -q 1 || \
su - postgres -c "psql -d ${DB_NAME} -f ${APP_DIR}/repo/database/schema.sql"

# 8. Backend dependencies
echo "8. Backend dependencies installeren..."
cd "$APP_DIR/repo/backend"
npm ci --omit=dev

# 9. Frontend bouwen
echo "9. Frontend bouwen..."
cd "$APP_DIR/repo/frontend"
npm ci
npm run build

# 10. Nginx configureren
echo "10. Nginx configureren..."
rm -rf /var/www/html/*
cp -r "$APP_DIR/repo/frontend/build"/* /var/www/html/

# Configureer reverse proxy
cat > /etc/nginx/conf.d/leningen-app.conf << 'EOF'
server {
    listen 80;
    server_name _;
    
    root /var/www/html;
    try_files $uri /index.html;
    
    location /api/ {
        proxy_pass http://127.0.0.1:3000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF

nginx -t && systemctl reload nginx

# 11. PM2 installeren
echo "11. PM2 installeren..."
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

# 12. Automatische login configureren
echo "12. Console autologin configureren..."
mkdir -p /etc/systemd/system/getty@tty1.service.d/
cat > /etc/systemd/system/getty@tty1.service.d/override.conf << 'EOF2'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM
EOF2
systemctl daemon-reload

echo "=== Installatie voltooid! ==="
echo "Webinterface beschikbaar op: http://$(hostname -I | awk '{print $1}')"
EOL

# Kopieer en voer het script uit in de container
echo "Script naar container kopiëren en uitvoeren..."
pct push $CTID setup-in-container.sh /root/setup.sh
pct exec $CTID -- chmod +x /root/setup.sh
pct exec $CTID -- bash /root/setup.sh

# Voltooi configuratie en optimaliseer resources
echo "Container optimaliseren..."
pct set $CTID --memory $FINAL_MEM --cores $FINAL_CORES

# Toon eindresultaat
CONTAINER_IP=$(pct exec $CTID -- hostname -I | tr -d '\r\n')
echo "============================="
echo "Installatie is voltooid!"
echo "Container ID: $CTID"
echo "Gebruiker: root"
echo "Wachtwoord: $PASSWORD"
echo "Webinterface: http://$CONTAINER_IP"
echo "============================="