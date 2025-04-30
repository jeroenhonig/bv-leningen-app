
markdown# BV Leningen App Installatie-instructies

Deze instructies beschrijven hoe u de BV Leningen App kunt installeren en configureren op een server.

## Vereisten

- Linux server (Alpine Linux aanbevolen voor LXC containers)
- PostgreSQL 12 of hoger
- Node.js 14 of hoger
- Nginx webserver
- Git

## Installatie in een Proxmox LXC container

### 1. LXC container aanmaken

In Proxmox VE:

```bash
# Container met Alpine Linux maken
pct create 100 local:vztmpl/alpine-3.17-default_20221129_amd64.tar.xz \
  --hostname leningen-app \
  --memory 512 \
  --swap 512 \
  --cores 1 \
  --rootfs local-lvm:8 \
  --password YourStrongPassword \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp
Start de container en log in:
bashpct start 100
pct enter 100
2. Basisinstallatie
bash# Update pakketbronnen
apk update
apk upgrade

# Installeer benodigde software
apk add bash curl wget git ca-certificates tzdata nano htop openrc
apk add postgresql postgresql-contrib
apk add nodejs npm
apk add nginx

# Tijdzone instellen
setup-timezone -z Europe/Amsterdam
3. PostgreSQL instellen
bash# Maak datamap aan
mkdir -p /var/lib/postgresql/data
chown postgres:postgres /var/lib/postgresql/data

# Initialiseer de database
su - postgres -c "initdb -D /var/lib/postgresql/data"

# PostgreSQL configureren om te starten bij boot
rc-update add postgresql default
rc-service postgresql start

# Database en gebruiker aanmaken
su - postgres -c "psql -c \"CREATE DATABASE leningen_db;\""
su - postgres -c "psql -c \"CREATE USER leningen_user WITH ENCRYPTED PASSWORD 'secure_password';\""
su - postgres -c "psql -c \"GRANT ALL PRIVILEGES ON DATABASE leningen_db TO leningen_user;\""

# Schema importeren
cd /tmp
git clone https://github.com/jeroenhonig/bv-leningen-app.git
su - postgres -c "psql -d leningen_db -f /tmp/bv-leningen-app/database/schema.sql"
4. Applicatie installeren
bash# Applicatiemap aanmaken
mkdir -p /opt/leningen-app
cd /opt/leningen-app

# Applicatie klonen
git clone https://github.com/jeroenhonig/bv-leningen-app.git .

# Backend installeren
cd backend
npm install
npm install -g pm2

# .env bestand maken
cat > .env << EOL
PORT=3000
DB_HOST=localhost
DB_PORT=5432
DB_NAME=leningen_db
DB_USER=leningen_user
DB_PASSWORD=secure_password
NODE_ENV=production
EOL

# Frontend bouwen
cd ../frontend
npm install
npm run build
5. Nginx configureren
bash# Nginx configuratiebestand maken
cat > /etc/nginx/http.d/leningen-app.conf << EOL
server {
    listen 80 default_server;
    server_name _;

    # Frontend bestanden
    location / {
        root /opt/leningen-app/frontend/build;
        index index.html;
        try_files \$uri \$uri/ /index.html;
    }

    # API endpoints
    location /api {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOL

# Controleer de configuratie
nginx -t

# Nginx configureren om te starten bij boot
rc-update add nginx default
rc-service nginx start
6. Applicatie starten
bash# Start de backend met PM2
cd /opt/leningen-app/backend
pm2 start server.js --name leningen-app

# PM2 configureren om te starten bij boot
pm2 startup
pm2 save
7. Backups instellen
bash# Backup script aanmaken
mkdir -p /opt/backups
cat > /opt/backups/backup.sh << EOL
#!/bin/sh
DATE=\$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_DIR="/opt/backups"
DB_NAME="leningen_db"
DB_USER="leningen_user"
DB_PASSWORD="secure_password"

# Maak PostgreSQL backup
PGPASSWORD="\$DB_PASSWORD" pg_dump -U "\$DB_USER" "\$DB_NAME" > "\$BACKUP_DIR/leningen_db_\$DATE.sql"

# Bewaar alleen laatste 10 backups
ls -t "\$BACKUP_DIR"/*.sql | tail -n +11 | xargs -r rm

# Log de backup
echo "Backup gemaakt op \$(date)" >> "\$BACKUP_DIR/backup_log.txt"
EOL

# Maak script uitvoerbaar
chmod +x /opt/backups/backup.sh

# Voeg toe aan cron
echo "0 3 * * * /opt/backups/backup.sh" | crontab -
Handmatige installatie op andere systemen
Voor installatie op andere systemen dan Alpine Linux:

Zorg voor een werkende PostgreSQL database
Maak de database en gebruiker aan
Importeer het schema
Clone de repository
Installeer de Node.js afhankelijkheden
Configureer de backend met de juiste database-instellingen
Bouw de frontend
Configureer een webserver om te verwijzen naar de frontend build en de API door te sturen naar de backend

Update procedure
Om de applicatie bij te werken:
bashcd /opt/leningen-app

# Maak een backup
/opt/backups/backup.sh

# Pull de laatste wijzigingen
git pull

# Update afhankelijkheden en bouw opnieuw
cd backend
npm install
cd ../frontend
npm install
npm run build

# Start de backend opnieuw
cd ../backend
pm2 restart leningen-app
