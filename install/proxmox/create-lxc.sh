#!/bin/bash
# Script voor het aanmaken van een Alpine Linux LXC container voor BV Leningen App
# Uitvoeren op de Proxmox host

# Configuratie
CTID=${1:-100}                  # Container ID, standaard 100
HOSTNAME=${2:-leningen-app}     # Hostname, standaard leningen-app
MEM=${3:-512}                   # Geheugen in MB, standaard 512
DISK=${4:-8}                    # Disk size in GB, standaard 8GB
CORES=${5:-1}                   # CPU cores, standaard 1
PASSWORD="$(openssl rand -base64 12)" # Willekeurig wachtwoord
IP_CONFIG=${6:-dhcp}            # IP configuratie, standaard dhcp
BRIDGE=${7:-vmbr0}              # Network bridge, standaard vmbr0
GITHUB_REPO="jeroenhonig/bv-leningen-app"

echo "BV Leningen App installatie starten..."
echo "Container ID: $CTID"
echo "Hostname: $HOSTNAME"
echo "Geheugen: $MEM MB"
echo "Schijfruimte: $DISK GB"
echo "CPU cores: $CORES"
echo "IP configuratie: $IP_CONFIG"
echo "Network bridge: $BRIDGE"

# Controleer of Alpine template bestaat
TEMPLATE_PATH=$(pveam list local | grep -o "local:vztmpl/alpine-[0-9]\+\.[0-9]\+-default_[0-9]\+_amd64\.tar\.xz" | sort -V | tail -n1)

if [ -z "$TEMPLATE_PATH" ]; then
    echo "Alpine template niet gevonden, wordt gedownload..."
    pveam update
    TEMPLATE_ID=$(pveam available --section system | grep alpine | grep -o "alpine-[0-9]\+\.[0-9]\+-default_[0-9]\+_amd64\.tar\.xz" | sort -V | tail -n1)
    pveam download local "$TEMPLATE_ID"
    TEMPLATE_PATH="local:vztmpl/$TEMPLATE_ID"
fi

# Controleer of container al bestaat
if pct list | grep -q "^$CTID\s"; then
    echo "Container $CTID bestaat al. Kies een ander ID of verwijder de bestaande container."
    exit 1
fi

# Maak de container aan
echo "Alpine Linux container ($CTID) aanmaken..."
pct create "$CTID" "$TEMPLATE_PATH" \
    --hostname "$HOSTNAME" \
    --memory "$MEM" \
    --swap 512 \
    --cores "$CORES" \
    --rootfs "local-lvm:$DISK" \
    --password "$PASSWORD" \
    --net0 "name=eth0,bridge=$BRIDGE,ip=$IP_CONFIG"

# Start de container
echo "Container starten..."
pct start "$CTID"

# Wacht tot de container volledig is opgestart
echo "Wachten tot container is opgestart..."
sleep 10

# Download en voer het setup script uit in de container
echo "Setup script downloaden en uitvoeren..."
pct exec "$CTID" -- ash -c "apk add curl && curl -s https://raw.githubusercontent.com/$GITHUB_REPO/main/install/lxc/setup.sh > /root/setup.sh && chmod +x /root/setup.sh && ash /root/setup.sh"

# Print informatie
IP_ADDRESS=$(pct exec "$CTID" -- ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
echo "------------------------------------"
echo "BV Leningen App installatie voltooid!"
echo "------------------------------------"
echo "Container ID: $CTID"
echo "Hostname: $HOSTNAME"
echo "IP-adres: $IP_ADDRESS"
echo "Root wachtwoord: $PASSWORD"
echo ""
echo "U kunt de applicatie nu openen in uw browser: http://$IP_ADDRESS"
echo "Bewaar dit wachtwoord op een veilige plaats!"
