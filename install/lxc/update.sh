#!/bin/ash
# Update script voor BV Leningen App
# Werkt de applicatie bij naar de nieuwste versie vanuit GitHub

# Configuratie
APP_DIR="/opt/leningen-app"
BACKUP_DIR="/opt/backups"
GITHUB_REPO="jeroenhonig/bv-leningen-app"
TIMESTAMP=$(date +%Y%m%d%H%M%S)

# Begin logging
LOG_FILE="/root/leningen-app-update-$TIMESTAMP.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "BV Leningen App update gestart op $(date)"

# 1. Maak backup
echo "1. Database backup maken..."
/opt/backups/backup.sh

# 2. Repository updaten
echo "2. Code updaten van GitHub..."
cd "$APP_DIR/repo"
git fetch origin
# Sla lokale wijzigingen op
git stash
# Update naar de nieuwste versie
git pull origin main

# 3. Backend updaten
echo "3. Backend updaten..."
cd "$APP_DIR/repo/backend"
npm install --production
pm2 stop leningen-app

# 4. Frontend updaten
echo "4. Frontend updaten..."
cd "$APP_DIR/repo/frontend"
npm install
npm run build

# 5. Services herstarten
echo "5. Services herstarten..."
cd "$APP_DIR/repo/backend"
pm2 start leningen-app
rc-service nginx restart

# Update voltooid
echo "=============================================="
echo "BV Leningen App Update Voltooid!"
echo "=============================================="
echo "Backup gemaakt in: $BACKUP_DIR"
echo "Update log: $LOG_FILE"
echo "=============================================="
