#!/bin/bash
set -eux

export DEBIAN_FRONTEND=noninteractive

echo "BV Leningen App installatie gestart op $(date)"

# 1. Systeem bijwerken
echo "1. Basissysteem bijwerken..."
apt-get update && apt-get upgrade -y

# 2. PostgreSQL installeren
echo "2. PostgreSQL installeren..."
apt-get install -y postgresql postgresql-contrib

# PostgreSQL wordt in een LXC vaak automatisch geïnitieerd
# maar we forceren het indien nodig:
PGDATA=$(find /etc/postgresql -name postgresql.conf | head -n1 | xargs dirname)
[ -d "$PGDATA" ] || su - postgres -c 'initdb -D /var/lib/postgresql/data'

# Start PostgreSQL indien nog niet draait
pg_ctlcluster $(pg_lsclusters | awk 'NR==2{print $1, $2}') start || true

# 3. Node.js installeren
echo "3. Node.js installeren..."
apt-get install -y curl gnupg
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# 4. Nginx installeren
echo "4. Nginx installeren..."
apt-get install -y nginx

# 5. Git & app clonen
echo "5. Applicatie clonen van GitHub..."
apt-get install -y git
mkdir -p /opt/leningen-app
cd /opt/leningen-app
git clone https://github.com/jeroenhonig/bv-leningen-app.git repo

# 6. Database configureren
echo "6. Database configureren..."
sudo -u postgres psql <<EOF
CREATE ROLE leningen_user WITH LOGIN PASSWORD 'leningen_pass';
CREATE DATABASE leningen_db OWNER leningen_user;
EOF
sudo -u postgres psql -d leningen_db < /opt/leningen-app/repo/database/schema.sql

# 7. Backend installeren
echo "7. Backend installeren..."
cd /opt/leningen-app/repo/backend
npm install

# 8. Frontend bouwen
echo "8. Frontend bouwen..."
cd /opt/leningen-app/repo/frontend
npm install
npm run build

# 9. Nginx configureren
echo "9. Nginx configureren..."
rm -rf /var/www/html/*
cp -r /opt/leningen-app/repo/frontend/build/* /var/www/html/

# 10. Backup (cron) installeren
echo "10. Backup configureren..."
apt-get install -y cron
service cron start

# 11. PM2 starten
echo "11. PM2 installeren en starten..."
npm install -g pm2
ln -sf "$(command -v pm2)" /usr/local/bin/pm2 || true
export PATH="$PATH:$(npm bin -g)"
cd /opt/leningen-app/repo/backend
pm2 start index.js --name leningen-backend
pm2 save

# 12. PostgreSQL optimaliseren
echo "12. PostgreSQL optimaliseren..."
PGCONF=$(find /etc/postgresql -name postgresql.conf | head -n1)
echo "shared_buffers = 64MB" >> "$PGCONF"
echo "work_mem = 4MB" >> "$PGCONF"
pg_ctlcluster $(pg_lsclusters | awk 'NR==2{print $1, $2}') restart || true

# 13. Health check uitvoeren
echo "13. Health check uitvoeren..."
if curl --fail http://localhost/api/ping >/dev/null 2>&1; then
  echo "✅ Backend is online"
else
  echo "❌ Backend is NIET bereikbaar - controleer PM2 of logs"
  echo "Gebruik bijvoorbeeld: pm2 logs of kijk in /opt/leningen-app/repo/backend"
fi

# Installatie voltooid
echo "=============================================="
echo "BV Leningen App Installatie Voltooid!"
echo "=============================================="
echo "Database naam: leningen_db"
echo "Database gebruiker: leningen_user"
echo "Database wachtwoord: leningen_pass"
echo "Web URL: http://$(hostname -I | awk '{print $1}')"
echo "=============================================="