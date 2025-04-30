#!/bin/bash
set -eux

get_next_ctid() {
  used_ids=$(pvesh get /cluster/resources --type vm --output-format json | jq -r '.[] | select(.vmid) | .vmid')
  for id in $(seq 100 999); do
    echo "$used_ids" | grep -qw $id || {
      echo $id
      return
    }
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

echo "BV Leningen App installatie starten..."
echo "Gekozen Container ID: $CTID"
echo "Hostname: $HOSTNAME"
echo "Tijdelijk geheugen: $INITIAL_MEM MB (later $FINAL_MEM MB)"
echo "Tijdelijk CPU cores: $INITIAL_CORES (later $FINAL_CORES)"
echo "Schijfruimte: $DISK GB"
echo "IP-configuratie: $IP_CONFIG"
echo "Netwerk bridge: $BRIDGE"

# Download juiste Debian template
pveam update
pveam list local | grep debian-12 || pveam download local debian-12-standard

TEMPLATE_PATH=$(pveam list local | grep -o 'local:vztmpl/debian-12[^ ]*\.tar\..*' | sort -V | tail -n1)

if [ -z "$TEMPLATE_PATH" ]; then
  echo "❌ Geen geschikte Debian template gevonden."
  exit 1
fi

pct create $CTID $TEMPLATE_PATH \
  --hostname $HOSTNAME \
  --memory $INITIAL_MEM \
  --swap 512 \
  --cores $INITIAL_CORES \
  --rootfs local-lvm:${DISK} \
  --password "$PASSWORD" \
  --net0 name=eth0,bridge=$BRIDGE,ip=$IP_CONFIG \
  --unprivileged 1 \
  --features nesting=1

echo "Container starten..."
pct start $CTID

echo "Wachten tot container is opgestart..."
sleep 10

echo "Setup script downloaden en uitvoeren..."
pct exec $CTID -- bash -c '
  apt update && apt install -y curl git &&
  curl -s https://raw.githubusercontent.com/'$GITHUB_REPO'/main/install/lxc/setup.sh > /root/setup.sh &&
  chmod +x /root/setup.sh &&
  bash /root/setup.sh
'