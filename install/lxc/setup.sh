#!/bin/sh
# Verbeterde setup.sh voor BV Leningen App op Alpine Linux
set -euxo pipefail

# 1. Basis packages installeren
apk update
apk add --no-cache git curl bash nodejs npm postgresql17 postgresql17-contrib postgresql17-openrc nginx nginx-openrc dcron dcron-openrc
npm install -g pm2

# 2. Clone applicatie
mkdir -p /opt/leningen-app
cd /opt/leningen-app
git clone https://github.com/jeroenhonig/bv-leningen-app repo

# 3. Database initialiseren
su - postgres -c "/usr/bin/initdb -D /var/lib/postgresql/17/data"
rc-update add postgresql
rc-service postgresql start

# 4. Database configureren
psql -U postgres <<EOF
CREATE USER leningen_user WITH PASSWORD 'leningen_pass';
CREATE DATABASE leningen_db OWNER leningen_user;
EOF
psql -U postgres -d leningen_db < /opt/leningen-app/repo/database/schema.sql

# 5. Backend installeren
cd /opt/leningen-app/repo/backend
npm install
pm run build

# 6. Frontend bouwen
cd /opt/leningen-app/repo/frontend
npm install
npm run build

# 7. Nginx configureren
mkdir -p /var/www/html
cp -r /opt/leningen-app/repo/frontend/build/* /var/www/html/
rc-update add nginx
rc-service nginx start

# 8. Backend met PM2 starten
cd /opt/leningen-app/repo/backend
pm install
pm run build
pm2 start dist/index.js --name leningen-app
pm2 save

# 9. PM2 autostart
pm install pm2 -g
pm2 startup | sh

# 10. Cron toevoegen
rc-update add dcron
rc-service dcron start

# 11. PostgreSQL optimalisatie voor kleine container
POSTGRES_CONF="/var/lib/postgresql/17/data/postgresql.conf"
if [ -f "$POSTGRES_CONF" ]; then
  echo "shared_buffers = 64MB" >> "$POSTGRES_CONF"
  echo "work_mem = 1MB" >> "$POSTGRES_CONF"
  rc-service postgresql restart
fi

# 12. Installatie voltooid
echo "=============================================="
echo "BV Leningen App Installatie Voltooid!"
echo "Database naam: leningen_db"
echo "Database gebruiker: leningen_user"
echo "Database wachtwoord: leningen_pass"
echo "Web URL: http://\$(hostname -i)"
echo "=============================================="
