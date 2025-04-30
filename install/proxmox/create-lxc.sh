#!/bin/bash
# Script voor het aanmaken van een Alpine Linux LXC container voor BV Leningen App
# Uitvoeren op een Proxmox-node (werkt in een cluster)

set -euxo pipefail

# Functie om het eerstvolgende vrije CTID te bepalen binnen de hele cluster
get_next_ctid() {
    local id=100
    local used_ids

    # Probeer clusterbrede CTID-lijst
    used_ids=$(pvesh get /cluster/resources --type vm 2>/dev/null | awk '{print $1}' | cut -d/ -f2 | grep -E '^[0-9]+$')

    # Als dat niets oplevert, gebruik lokale containerlijst
    if [ -z "$used_ids" ]; then
        echo "⚠️  Waarschuwing: geen clusterbrede containers gevonden, val terug op lokale lijst"
        used_ids=$(pct list | awk 'NR>1 {print $1}')
    fi

    while echo "$used_ids" | grep -qw "$id"; do
        ((id++))
    done
    echo "$id"
}

# Bepaal automatisch het eerstvolgende vrije CTID
CTID="$(get_next_ctid)"

# Configuratie
HOSTNAME=${1:-leningen-app}
INITIAL_MEM=2048
FINAL_MEM=512
INITIAL_CORES=4
FINAL_CORES=1
DISK=${2:-8}
PASSWORD="$(openssl rand -base64 12)"
IP_CONFIG=${3:-dhcp}
BRIDGE=${4:-vmbr0}
GITHUB_REPO="jeroenhonig/bv-leningen-app"

echo "BV Leningen App installatie starten..."
echo "Gekozen Container ID: $CTID"
echo "Hostname: $HOSTNAME"
echo "Tijdelijk geheugen: $INITIAL_MEM MB (later $FINAL_MEM MB)"
echo "Tijdelijk CPU cores: $INITIAL_CORES (later $FINAL_CORES)"
echo "Schijfruimte: $DISK GB"
echo "IP-configuratie: $IP_CONFIG"
echo "Netwerk bridge: $BRIDGE"

# Controleer of Alpine template aanwezig is
TEMPLATE_PATH=$(pveam list local | grep -o "local:vztmpl/alpine-[0-9]\+\.[0-9]\+-default_[0-9]\+_amd64\.tar\.xz" | sort -V | tail -n1)

if [ -z "$TEMPLATE_PATH" ]; then
    echo "Alpine template niet gevonden, wordt gedownload..."
    pveam update
    TEMPLATE_ID=$(pveam available --section system | grep alpine | grep -o "alpine-[0-9]\+\.[0-9]\+-default_[0-9]\+_amd64\.tar\.xz" | sort -V | tail -n1)
    pveam download local "$TEMPLATE_ID"
    TEMPLATE_PATH="local:vztmpl/$TEMPLATE_ID"
fi

# Voor de zekerheid: controleer of container lokaal bestaat
if pct list | awk 'NR>1 {print $1}' | grep -qw "$CTID"; then
    echo "Container $CTID bestaat al op deze node. Kies een ander ID of verwijder de container."
    exit 1
fi

# Container aanmaken
echo "Alpine Linux container ($CTID) aanmaken..."
pct create "$CTID" "$TEMPLATE_PATH" \
    --hostname "$HOSTNAME" \
    --memory "$INITIAL_MEM" \
    --swap 512 \
    --cores "$INITIAL_CORES" \
    --rootfs "local-lvm:$DISK" \
    --password "$PASSWORD" \
    --net0 "name=eth0,bridge=$BRIDGE,ip=$IP_CONFIG"

# Start container
echo "Container starten..."
pct start "$CTID"

echo "Wachten tot container is opgestart..."
sleep 10

# Setup script uitvoeren
echo "Setup script downloaden en uitvoeren..."
pct exec "$CTID" -- ash -c "
  apk add curl &&
  curl -s https://raw.githubusercontent.com/$GITHUB_REPO/main/install/lxc/setup.sh > /root/setup.sh &&
  chmod +x /root/setup.sh &&
  ash /root/setup.sh
"

# Resources terugschakelen
echo "Containerresources terugschalen naar cores=$FINAL_CORES en geheugen=${FINAL_MEM}MB..."
pct set "$CTID" --cores "$FINAL_CORES" --memory "$FINAL_MEM"

# IP-adres ophalen
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