#!/bin/bash
set -eux

# Controleer en installeer jq indien nodig
if ! command -v jq &> /dev/null; then
    apt-get update && apt-get install -y jq
fi

get_next_ctid() {
  used_ids=$(pvesh get /cluster/resources --type vm --output-format json | jq -r '.[] | select(.vmid) | .vmid')
  for id in $(seq 100 999); do
    echo "$used_ids" | grep -qw "$id" || { echo "$id"; return; }
  done
}

CTID=$(get_next_ctid)
HOSTNAME="leningen-app"
INITIAL_MEM=2048
FINAL_MEM=512
INITIAL_CORES=4
FINAL_CORES=1
DISK=8
PASSWORD=$(openssl rand -base64 12)
IP_CONFIG="dhcp"
BRIDGE="vmbr0"
GITHUB_REPO="jeroenhonig/bv-leningen-app"

# Zoek de laatste standaard debian-12 template en download deze
TEMPLATE_FILE=$(pveam available | grep -o 'debian-12-standard[^ ]*\.tar\.\(gz\|xz\|zst\)' | sort -V | tail -n1)
pveam download local "$TEMPLATE_FILE"
TEMPLATE_PATH="local:vztmpl/$TEMPLATE_FILE"

echo "BV Leningen App installatie starten..."
echo "Gekozen Container ID: $CTID"
echo "Hostname: $HOSTNAME"
echo "Tijdelijk geheugen: $INITIAL_MEM MB (later $FINAL_MEM MB)"
echo "Tijdelijk CPU cores: $INITIAL_CORES (later $FINAL_CORES)"
echo "Schijfruimte: $DISK GB"
echo "IP-configuratie: $IP_CONFIG"
echo "Netwerk bridge: $BRIDGE"
echo "Debian template: $TEMPLATE_PATH"

# Container aanmaken zonder --lock 0 parameter
pct create $CTID $TEMPLATE_PATH \
  --hostname $HOSTNAME \
  --memory $INITIAL_MEM \
  --swap 512 \
  --cores $INITIAL_CORES \
  --rootfs local-lvm:$DISK \
  --password "$PASSWORD" \
  --net0 name=eth0,bridge=$BRIDGE,ip=$IP_CONFIG \
  --unprivileged 1 \
  --features nesting=1

echo "Container starten..."
pct start $CTID
echo "Wachten tot container is opgestart..."
sleep 10

echo "Opgeschoonde setup.sh aanmaken en uitvoeren..."
pct exec $CTID -- bash -c "cat > /root/setup.sh <<'EOF'
#!/usr/bin/env bash
# Debian-slim install script for the **BV Leningen App** inside an LXC container
# - Tested on Debian 12 (bookworm-slim) template
# - Idempotent: safe to rerun
# - Designed for low-resource CTs (512 MB RAM)

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
APP_DIR=\"/opt/leningen-app\"
REPO=\"jeroenhonig/bv-leningen-app\"
DB_USER=\"leningen_user\"
DB_PASS=\"leningen_pass\"
DB_NAME=\"leningen_db\"
NODE_VERSION=\"20\"          # major Node LTS we want
PG_CONF_OVERRIDES=(
  \"shared_buffers = 64MB\"
  \"work_mem       = 4MB\"
)

echo \"==========  BV Leningen App install  \$(date)  ==========\" 

log() { echo -e \"\n\e[1;34m\$*\e[0m\"; }

###############################################################################
# 1. Base system update
###############################################################################
log \"1. Pakketlijsten bijwerken\"
apt-get update -qq
apt-get upgrade -y -qq

###############################################################################
# 2. PostgreSQL
###############################################################################
log \"2. PostgreSQL installeren\"
apt-get install -y -qq postgresql postgresql-contrib

# Zorg dat er een cluster draait (Debian maakt er normaliter al een)