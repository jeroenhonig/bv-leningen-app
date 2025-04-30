#!/bin/bash
set -eux

get_next_ctid() {
  used_ids=$(pvesh get /cluster/resources --type vm --output-format json | jq -r '.[] | select(.vmid) | .vmid')
  for id in $(seq 100 999); do
    echo "$used_ids" | grep -qw "$id" || { echo "$id"; return; }
  done
}

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
GITHUB_REPO="jeroenhonig/bv-leningen-app"

# Zoek de laatste standaard debian-12 template en download deze
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

pct create $CTID $TEMPLATE_PATH \
  --hostname $HOSTNAME \
  --memory $INITIAL_MEM \
  --swap 512 \
  --cores $INITIAL_CORES \
  --rootfs local-lvm:$DISK \
  --password "$PASSWORD" \
  --net0 name=eth0,bridge=$BRIDGE,ip=$IP_CONFIG \
  --unprivileged 1 \
  --features nesting=1 \
  --lock 0

echo "Container starten..."
pct start $CTID
echo "Wachten tot container is opgestart..."
sleep 10

echo "Opgeschoonde setup.sh aanmaken en uitvoeren..."
pct exec $CTID -- bash -c "cat > /root/setup.sh <<'EOF'
#!/usr/bin/env bash
# Debian-slim install script for the **BV Leningen App** inside an LXC container
# - Tested on Debian 12 (bookworm-slim) template
# - Idempotent: safe to rerun
# - Designed for low-resource CTs (512 MB RAM)

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
APP_DIR=\"/opt/leningen-app\"
REPO=\"jeroenhonig/bv-leningen-app\"
DB_USER=\"leningen_user\"
DB_PASS=\"leningen_pass\"
DB_NAME=\"leningen_db\"
NODE_VERSION=\"20\"          # major Node LTS we want
PG_CONF_OVERRIDES=(
  \"shared_buffers = 64MB\"
  \"work_mem       = 4MB\"
)

echo \"==========  BV Leningen App install  \$(date)  ==========\" 

log() { echo -e \"\n\e[1;34m\$*\e[0m\"; }

###############################################################################
# 1. Base system update
###############################################################################
log \"1. Pakketlijsten bijwerken\"
apt-get update -qq
apt-get upgrade -y -qq

###############################################################################
# 2. PostgreSQL
###############################################################################
log \"2. PostgreSQL installeren\"
apt-get install -y -qq postgresql postgresql-contrib

# Zorg dat er een cluster draait (Debian maakt er normaliter al een)
if ! pg_lsclusters | grep -q \"^15[[:space:]]\+main\"; then
  log \"Geen bestaande 15/main cluster gevonden, initialiseren\"
  pg_createcluster 15 main --start
fi
pg_ctlcluster 15 main start || true

###############################################################################
# 3. Node.js (via NodeSource) + incl. SSL roots
###############################################################################
log \"3. Node.js installeren\"
apt-get install -y -qq curl gnupg ca-certificates
if ! command -v node >/dev/null; then
  curl -fsSL \"https://deb.nodesource.com/setup_\${NODE_VERSION}.x\" | bash -
  apt-get install -y -qq nodejs
fi

###############################################################################
# 4. Webserver
###############################################################################
log \"4. Nginx installeren\"
# Verwijder (TurnKey) Apache als die al poort 80 claimt
systemctl disable --now apache2 2>/dev/null || true
apt-get install -y -qq nginx
systemctl enable --now nginx

###############################################################################
# 5. Git & code ophalen
###############################################################################
log \"5. Applicatie clonen\"
apt-get install -y -qq git
mkdir -p \"\$APP_DIR\"
cd \"\$APP_DIR\"
if [ ! -d repo/.git ]; then
  git clone \"https://github.com/\${REPO}.git\" repo
else
  (cd repo && git pull --ff-only)
fi

###############################################################################
# 6. Database configureren
###############################################################################
log \"6. Database configureren\"

# 6a. Role aanmaken (negeer \"already exists\")
su - postgres -c \"psql -v ON_ERROR_STOP=1 -c \\\"CREATE ROLE \${DB_USER} WITH LOGIN PASSWORD '\${DB_PASS}';\\\" || true\"

# 6b. Database aanmaken (negeer \"database already exists\")
su - postgres -c \"psql -v ON_ERROR_STOP=1 -c \\\"CREATE DATABASE \${DB_NAME} OWNER \${DB_USER};\\\" || true\"

# ---- schema importeren, alleen als het nog niet staat ---------------------
su - postgres -c \"psql -d \${DB_NAME} -tAc \\
  \\\"SELECT 1 FROM information_schema.tables WHERE table_name = 'lening'\\\"\" \\
  | grep -q 1 || \\
  su - postgres -c \"psql -d \${DB_NAME} -f \${APP_DIR}/repo/database/schema.sql\"

###############################################################################
# 7. Backend dependencies (prod-only)  
###############################################################################
log \"7. Backend dependencies installeren\"
cd \"\$APP_DIR/repo/backend\"
# ci i.p.v. install voor repeatability, alleen runtime deps
npm ci --omit=dev

###############################################################################
# 8. Front-end build
###############################################################################
log \"8. Front-end builden\"
cd \"\$APP_DIR/repo/frontend\"
npm ci  # dev-deps nodig om te builden
npm run build

###############################################################################
# 9. Nginx webroot vullen
###############################################################################
log \"9. Nginx configureren\"
rm -rf /var/www/html/*
cp -r \"\$APP_DIR/repo/frontend/build\"/* /var/www/html/

# Optioneel: eenvoudige reverse-proxy zodat /api traffic naar backend gaat
cat >/etc/nginx/conf.d/leningen-app.conf <<'NGINX'
server {
    listen 80;
    server_name _;

    # serveer je SPA
    root /var/www/html;
    try_files \$uri /index.html;

    # proxy /api/* naar je backend
    location /api/ {
        proxy_pass http://127.0.0.1:3000/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
NGINX

nginx -t && systemctl reload nginx

###############################################################################
# 10. Cron/backup placeholder
###############################################################################
log \"10. Cron inschakelen\"
apt-get install -y -qq cron
systemctl enable --now cron

###############################################################################
# 11. PM2 runtime
###############################################################################
log \"11. PM2 installeren & backend starten\"
if ! command -v pm2 >/dev/null; then npm install -g pm2; fi
pm2 startup systemd -u root --hp /root --silent
cd \"\$APP_DIR/repo/backend\"
# kijk eerst welk bestand er echt is
if [ -f index.js ]; then
  pm2 start index.js --name leningen-backend --time --update-env
elif [ -f server.js ]; then
  pm2 start server.js --name leningen-backend --time --update-env
else
  # of via npm-script
  pm2 start npm --name leningen-backend -- run start --update-env
fi
pm2 save

###############################################################################
# 12. PostgreSQL fine-tuning (enkel 1x toevoegen)
###############################################################################
log \"12. PostgreSQL tweaken\"
PGCONF=\$(find /etc/postgresql -name postgresql.conf | head -n1)
for line in \"\${PG_CONF_OVERRIDES[@]}\"; do
  grep -q \"^\${line%% *}\" \"\$PGCONF\" || echo \"\$line\" >> \"\$PGCONF\"
done
pg_ctlcluster 15 main reload

###############################################################################
# 13. Health-check
###############################################################################
log \"13. Health-check\"
if curl -fs http://localhost/api/ping >/dev/null; then
  echo \"✅ Backend beantwoordt /api/ping\"
else
  echo \"❌ Geen response van backend - check 'pm2 logs'\"
fi

###############################################################################
# 14. Set root password (als dit nodig is)
###############################################################################
# NEW_ROOT_PASS=\"\$(openssl rand -base64 12)\"
# echo \"root:\${NEW_ROOT_PASS}\" | chpasswd
# echo -e \"\n🔑 Root password is: \${NEW_ROOT_PASS}\n\"

echo -e \"\n✅ Installatie voltooid. Web: http://\$(hostname -I | awk '{print \$1}') !\"
EOF"

# Script uitvoerbaar maken en uitvoeren
pct exec $CTID -- bash -c "chmod +x /root/setup.sh && bash /root/setup.sh"

# Container optimaliseren na de installatie
echo "Bronnen aanpassen naar definitieve waarden..."
pct resize $CTID rootfs ${DISK}G
pct set $CTID --memory $FINAL_MEM --cores $FINAL_CORES

echo "Installatie voltooid! Je kunt inloggen op de container met:"
echo "pct enter $CTID"
echo "Root wachtwoord is: $PASSWORD"