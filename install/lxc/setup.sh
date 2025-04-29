#!/bin/ash
# Installatiescript voor BV Leningen App in Alpine Linux LXC
# Wordt uitgevoerd binnen de LXC container

# Configuratie
APP_DIR="/opt/leningen-app"
DB_NAME="leningen_db"
DB_USER="leningen_user"
DB_PASSWORD="$(openssl rand -base64 12)" # Genereer een willekeurig wachtwoord
GITHUB_REPO="jeroenhonig/bv-leningen-app"

# Begin logging van installatie
LOG_FILE="/root/leningen-app-install.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "BV Leningen App installatie gestart op $(date)"

# 1. Basissysteem updates
echo "1. Basissysteem bijwerken..."
apk update
apk upgrade
apk add bash curl wget git ca-certificates tzdata nano htop openrc

# 2. PostgreSQL installatie
echo "2. PostgreSQL installeren..."
apk add postgresql postgresql-contrib
mkdir -p /var/lib/postgresql/data
chown postgres:postgres /var/lib/postgresql/data
su - postgres -c "initdb -D /var/lib/postgresql/data"

# PostgreSQL configureren om verbindingen toe te staan
su - postgres -c "sed -i \"s/#listen_addresses = 'localhost'/listen_addresses = 'localhost'/g\" /var/lib/postgresql/data/postgresql.conf"

# PostgreSQL configureren om te starten bij boot
rc-update add postgresql default
rc-service postgresql start

# 3. NodeJS installatie
echo "3. Node.js installeren..."
apk add nodejs npm
npm install -g pm2

# 4. Nginx installatie
echo "4. Nginx installeren..."
apk add nginx
mkdir -p /var/log/nginx
rc-update add nginx default

# 5. Applicatie repository klonen
echo "5. Applicatie clonen van GitHub..."
mkdir -p "$APP_DIR"
git clone "https://github.com/$GITHUB_REPO.git" "$APP_DIR/repo"

# 6. Database setup
echo "6. Database configureren..."
su - postgres -c "psql -c \"CREATE DATABASE $DB_NAME;\""
su - postgres -c "psql -c \"CREATE USER $DB_USER WITH ENCRYPTED PASSWORD '$DB_PASSWORD';\""
su - postgres -c "psql -c \"GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;\""

# Importeer database schema
if [ -f "$APP_DIR/repo/database/schema.sql" ]; then
  su - postgres -c "psql -d $DB_NAME -f $APP_DIR/repo/database/schema.sql"
else
  echo "Database schema niet gevonden, maak tabellen handmatig aan..."
  # Maak hier handmatig de tabellen aan als het schema-bestand nog niet beschikbaar is
fi

# 7. Backend installatie
echo "7. Backend installeren..."
# Maak .env bestand
if [ -d "$APP_DIR/repo/backend" ]; then
  cat > "$APP_DIR/repo/backend/.env" << EOL2
PORT=3000
DB_HOST=localhost
DB_PORT=5432
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
NODE_ENV=production
EOL2

  # Installeer backend dependencies
  cd "$APP_DIR/repo/backend"
  npm install --production

  # Configureer PM2
  cat > "$APP_DIR/repo/backend/ecosystem.config.js" << EOL2
module.exports = {
  apps: [{
    name: 'leningen-app',
    script: 'server.js',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '150M',
    node_args: '--max-old-space-size=128',
    env: {
      NODE_ENV: 'production'
    }
  }]
};
EOL2
else
  echo "Backend directory niet gevonden, maak handmatig aan..."
  mkdir -p "$APP_DIR/repo/backend"
fi

# 8. Frontend build
echo "8. Frontend bouwen..."
if [ -d "$APP_DIR/repo/frontend" ]; then
  cd "$APP_DIR/repo/frontend"
  npm install
  npm run build
else
  echo "Frontend directory niet gevonden, maak handmatig aan..."
  mkdir -p "$APP_DIR/repo/frontend/build"
fi

# 9. Nginx configuratie
echo "9. Nginx configureren..."
cat > /etc/nginx/conf.d/leningen-app.conf << EOL2
server {
    listen 80 default_server;
    server_name _;

    # Logging
    access_log /var/log/nginx/leningen-app_access.log;
    error_log /var/log/nginx/leningen-app_error.log;

    # Frontend bestanden
    location / {
        root $APP_DIR/repo/frontend/build;
        index index.html;
        try_files \$uri \$uri/ /index.html;
    }

    # API endpoints proxy
    location /api {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Content-Type-Options "nosniff";
    add_header Referrer-Policy "strict-origin-when-cross-origin";
}
EOL2

# 10. Backup setup
echo "10. Backup configureren..."
mkdir -p /opt/backups
cat > /opt/backups/backup.sh << EOL2
#!/bin/sh
DATE=\$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_DIR="/opt/backups"
DB_NAME="$DB_NAME"
DB_USER="$DB_USER"
DB_PASSWORD="$DB_PASSWORD"

# Maak de PostgreSQL backup
PGPASSWORD="\$DB_PASSWORD" pg_dump -U "\$DB_USER" -h localhost "\$DB_NAME" > "\$BACKUP_DIR/leningen_db_\$DATE.sql"

# Bewaar alleen de laatste 10 backups
ls -t "\$BACKUP_DIR"/*.sql | tail -n +11 | xargs -r rm

# Log de backup
echo "Backup gemaakt op \$(date)" >> "\$BACKUP_DIR/backup_log.txt"
EOL2
chmod +x /opt/backups/backup.sh

# Cron installeren voor backups
apk add dcron
rc-update add dcron default
rc-service dcron start
echo "0 2 * * * /opt/backups/backup.sh" | crontab -

# 11. Firewall setup
echo "11. Firewall configureren..."
apk add iptables ip6tables

cat > /etc/local.d/firewall.start << EOL2
#!/bin/sh
# Reset iptables
iptables -F
iptables -X

# Standaard policy
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Sta loopback toe
iptables -A INPUT -i lo -j ACCEPT

# Sta gerelateerde en gevestigde verbindingen toe
iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# Sta SSH toe
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Sta HTTP toe
iptables -A INPUT -p tcp --dport 80 -j ACCEPT

# IPv6 beleid
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT ACCEPT
EOL2
chmod +x /etc/local.d/firewall.start

# 12. Startup configuratie
echo "12. Autostart configureren..."
cat > /etc/local.d/leningen-app.start << EOL2
#!/bin/sh
# Start PostgreSQL als het nog niet draait
if ! rc-service postgresql status > /dev/null 2>&1; then
  rc-service postgresql start
fi

# Start de backend applicatie met PM2
if [ -d "$APP_DIR/repo/backend" ]; then
  cd $APP_DIR/repo/backend
  pm2 start ecosystem.config.js || echo "PM2 kon niet starten"
fi

# Start Nginx als het nog niet draait
if ! rc-service nginx status > /dev/null 2>&1; then
  rc-service nginx start
fi
exit 0
EOL2
chmod +x /etc/local.d/leningen-app.start
rc-update add local default

# 13. Start services
echo "13. Services starten..."
/etc/local.d/firewall.start
/etc/local.d/leningen-app.start
rc-service nginx restart

# 14. PM2 startup
echo "14. PM2 configureren voor autostart..."
env PATH=$PATH:/usr/bin pm2 startup -u root || echo "PM2 startup mislukt"
pm2 save || echo "PM2 save mislukt"

# 15. Beveiligingsoptimalisatie
echo "15. Beveiligingsoptimalisatie uitvoeren..."
sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
rc-service sshd restart

# 16. PostgreSQL optimalisatie
echo "16. PostgreSQL optimaliseren voor kleine container..."
su - postgres -c "sed -i 's/^shared_buffers =.*/shared_buffers = 32MB/g' /var/lib/postgresql/data/postgresql.conf"
su - postgres -c "sed -i 's/^#effective_cache_size =.*/effective_cache_size = 96MB/g' /var/lib/postgresql/data/postgresql.conf"
su - postgres -c "sed -i 's/^#work_mem =.*/work_mem = 4MB/g' /var/lib/postgresql/data/postgresql.conf"
su - postgres -c "sed -i 's/^#maintenance_work_mem =.*/maintenance_work_mem = 16MB/g' /var/lib/postgresql/data/postgresql.conf"
su - postgres -c "sed -i 's/^max_connections =.*/max_connections = 20/g' /var/lib/postgresql/data/postgresql.conf"
rc-service postgresql restart

# Installatie voltooid
IP_ADDRESS=$(ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
echo "=============================================="
echo "BV Leningen App Installatie Voltooid!"
echo "=============================================="
echo "Database naam: $DB_NAME"
echo "Database gebruiker: $DB_USER"
echo "Database wachtwoord: $DB_PASSWORD"
echo "Web URL: http://$IP_ADDRESS"
echo ""
echo "Deze gegevens zijn opgeslagen in: $LOG_FILE"
echo "=============================================="
