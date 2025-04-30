#!/bin/ash
set -eux

echo "BV Leningen App installatie gestart op $(date)"

echo "1. Basissysteem bijwerken..."
apk update
apk upgrade

echo "2. PostgreSQL installeren..."
apk add postgresql17 postgresql17-contrib postgresql17-openrc postgresql-common postgresql-common-openrc

su - postgres -c '/usr/bin/initdb -D /var/lib/postgresql/17/data'
rc-update add postgresql
rc-service postgresql start

echo "3. Node.js installeren..."
apk add nodejs npm

echo "4. Nginx installeren..."
apk add nginx nginx-openrc
rc-update add nginx

echo "5. Applicatie clonen van GitHub..."
apk add git
mkdir -p /opt/leningen-app
cd /opt/leningen-app
git clone https://github.com/jeroenhonig/bv-leningen-app.git repo

echo "6. Database configureren..."
psql -U postgres <<EOF
CREATE ROLE leningen_user WITH LOGIN PASSWORD 'leningen_pass';
CREATE DATABASE leningen_db OWNER leningen_user;
EOF

psql -U postgres -d leningen_db < /opt/leningen-app/repo/database/schema.sql

echo "7. Backend installeren..."
cd /opt/leningen-app/repo/backend
npm install

echo "8. Frontend bouwen..."
cd /opt/leningen-app/repo/frontend
npm install
npm run build

echo "9. Nginx configureren..."
rm -rf /var/www/localhost/htdocs/*
cp -r /opt/leningen-app/repo/frontend/build/* /var/www/localhost/htdocs/

echo "10. Backup configureren..."
apk add dcron dcron-openrc
rc-update add dcron
rc-service dcron start

echo "11. Services starten..."
npm install -g pm2
cd /opt/leningen-app/repo/backend
pm2 start index.js --name leningen-backend
pm2 save
rc-service nginx start

echo "12. PostgreSQL optimaliseren voor kleine container..."
echo "shared_buffers = 64MB" >> /var/lib/postgresql/17/data/postgresql.conf
echo "work_mem = 4MB" >> /var/lib/postgresql/17/data/postgresql.conf
rc-service postgresql restart

echo "=============================================="
echo "BV Leningen App Installatie Voltooid!"
echo "=============================================="
echo "Database naam: leningen_db"
echo "Database gebruiker: leningen_user"
echo "Database wachtwoord: leningen_pass"
echo "Web URL: http://$(ip -4 addr show eth0 | awk '/inet / {print $2}' | cut -d/ -f1)"
echo ""
echo "Deze gegevens zijn opgeslagen in: /root/leningen-app-install.log"
echo "=============================================="