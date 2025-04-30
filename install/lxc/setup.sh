#!/bin/ash

export NODE_OPTIONS="--max-old-space-size=1024"

echo "BV Leningen App installatie gestart op $(date)"

echo "1. Basissysteem bijwerken..."
apk update && apk upgrade

echo "2. PostgreSQL installeren..."
apk add postgresql17 postgresql17-contrib

if [ ! -f "/var/lib/postgres/PG_VERSION" ]; then
    su postgres -c 'initdb -D /var/lib/postgres'
else
    echo "PostgreSQL database directory bestaat al, overslaan..."
fi

rc-update add postgresql default
rc-service postgresql start

echo "3. Node.js installeren..."
apk add nodejs npm

echo "4. Nginx installeren..."
apk add nginx
rc-update add nginx default

echo "5. Applicatie clonen van GitHub..."
mkdir -p /opt/leningen-app
if [ ! -d "/opt/leningen-app/repo/.git" ]; then
    git clone https://github.com/jeroenhonig/bv-leningen-app.git /opt/leningen-app/repo
else
    echo "Repository bestaat al, wordt overgeslagen..."
fi

echo "6. Database configureren..."
su postgres -c 'psql -c "CREATE USER leningen_user WITH PASSWORD '\''leningen_pass'\'';"' || true
su postgres -c 'psql -c "CREATE DATABASE leningen_db OWNER leningen_user;"' || true
su postgres -c 'psql leningen_db -f /opt/leningen-app/repo/database/schema.sql' || true

echo "7. Backend installeren..."
cd /opt/leningen-app/repo/backend
npm install

echo "8. Frontend bouwen..."
cd /opt/leningen-app/repo/frontend
npm install
npm run build

echo "9. Nginx configureren..."
mkdir -p /var/www/leningen-app
cp -r /opt/leningen-app/repo/frontend/build/* /var/www/leningen-app/

cat > /etc/nginx/http.d/leningen-app.conf <<EOF
server {
    listen 80;
    server_name _;

    root /var/www/leningen-app;
    index index.html;

    location /api/ {
        proxy_pass http://localhost:3000/api/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }

    location / {
        try_files \$uri /index.html;
    }
}
EOF

# Fix voor dubbele default_server fout
sed -i 's/listen 80 default_server;/listen 80;/' /etc/nginx/http.d/*.conf || true

echo "10. Backup configureren..."
apk add dcron
rc-update add dcron default
rc-service dcron start

echo "11. Services starten..."
apk add pm2
npm install -g pm2
cd /opt/leningen-app/repo/backend
pm2 start server.js --name leningen-app
pm2 startup openrc -u root --hp /root
pm2 save

rc-service nginx restart

echo "12. PostgreSQL optimaliseren voor kleine container..."
echo "shared_buffers = 64MB" >> /etc/postgresql/17/postgresql.conf
echo "max_connections = 20" >> /etc/postgresql/17/postgresql.conf
rc-service postgresql restart

echo "=============================================="
echo "BV Leningen App Installatie Voltooid!"
echo "=============================================="
echo "Database naam: leningen_db"
echo "Database gebruiker: leningen_user"
echo "Database wachtwoord: leningen_pass"
echo "Web URL: http://$(ip -4 a show eth0 | awk '/inet / {print $2}' | cut -d/ -f1)"
echo ""
echo "Deze gegevens zijn opgeslagen in: /root/leningen-app-install.log"
echo "=============================================="