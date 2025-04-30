#!/bin/bash
# Script voor het aanmaken van een Alpine Linux LXC container voor BV Leningen App
# Uitvoeren op de Proxmox host

set -euo pipefail

# Functie om eerstvolgende vrije CTID te bepalen
get_next_ctid() {
    local id=100
    while pct list | awk 'NR>1 {print $1}' | grep -qw "$id"; do
        ((id++))
    done
    echo "$id"
}

# Configuratie met betrouwbare CTID-keuze
if [ -n "${1:-}" ]; then
  CTID="$1"
else
  CTID=$(get_next_ctid)
fi

HOSTNAME=${2:-leningen-app}         # Hostname
INITIAL_MEM=2048                    # Tijdelijk geheugen (MB)
FINAL_MEM=512                       # Geheugen na installatie (MB)
INITIAL_CORES=4                     # Tijdelijk aantal cores
FINAL_CORES=1                       # Cores na installatie
DISK=${3:-8}                         # Disk size in GB
PASSWORD="$(openssl rand -base64 12)" # Root wachtwoord
IP_CONFIG=${4:-dhcp}                # IP-configuratie
BRIDGE=${5:-vmbr0}                  # Netwerk bridge
GITHUB_REPO="jeroenhonig/bv-leningen-app"

echo "BV Leningen App installatie starten..."
echo "Gekozen Container ID: $CTID"
echo "Hostname: $HOSTNAME"
echo "Tijdelijk geheugen: $INITIAL_MEM MB (later $FINAL_MEM MB)"
echo "Tijdelijk CPU cores: $INITIAL_CORES (later $FINAL_CORES)"
echo "Schijfruimte: $DISK GB"
echo "IP-configuratie: $IP_CONFIG"
echo "Netwerk bridge: $BRIDGE"

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
if pct list | awk 'NR>1 {print $1}' | grep -qw "$CTID"; then
    echo "Container $CTID bestaat al. Kies een ander ID of verwijder de bestaande container."
    exit 1
fi

# Maak de container aan
echo "Alpine Linux container ($CTID) aanmaken..."
pct create "$CTID" "$TEMPLATE_PATH" \
    --hostname "$HOSTNAME" \
    --memory "$INITIAL_MEM" \
    --swap 512 \
    --cores "$INITIAL_CORES" \
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
pct exec "$CTID" -- ash -c "
  apk add curl &&
  curl -s https://raw.githubusercontent.com/$GITHUB_REPO/main/install/lxc/setup.sh > /root/setup.sh &&
  chmod +x /root/setup.sh &&
  ash /root/setup.sh
"

# Breng resources terug naar productie-instellingen
echo "Containerresources terugschalen naar cores=$FINAL_CORES en geheugen=${FINAL_MEM}MB..."
pct set "$CTID" --cores "$FINAL_CORES" --memory "$FINAL_MEM"

# Print informatie
IP_ADDRESS=$(pct exec "$CTID" -- ip -4 addr show eth0 | awk '/inet / {print $2}' | cut -d/ -f1)
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