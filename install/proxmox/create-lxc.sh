#!/bin/bash
set -eux

# === create-lxc.sh ===
# Maak een nieuwe LXC container met Debian slim template op Proxmox

get_next_ctid() {
  used_ids=$(pvesh get /cluster/resources --type vm --output-format json | jq -r '.[] | select(.vmid) | .vmid')
  for id in $(seq 100 999); do
    if ! echo "$used_ids" | grep -qw "$id"; then
      echo "$id"
      return
    fi
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

# Zorg dat het template beschikbaar is
TEMPLATE_PATH=$(pveam available | grep 'debian-12' | sort -V | tail -n1 | awk '{print $1}')

if [ -z "$TEMPLATE_PATH" ]; then
  echo "Geen Debian 12 template gevonden. Download eerst via 'pveam update && pveam download local debian-12-standard'"
  exit 1
fi

pct create $CTID $TEMPLATE_PATH \
  --hostname $HOSTNAME \
  --memory $INITIAL_MEM \
  --swap 512 \
  --cores $INITIAL_CORES \
  --rootfs local-lvm:$DISK \
  --password $PASSWORD \
  --net0 name=eth0,bridge=$BRIDGE,ip=$IP_CONFIG \
  --unprivileged 1 \
  --features nesting=1

pct start $CTID
sleep 10

pct exec $CTID -- bash -c "apt update && apt install -y curl"
pct exec $CTID -- bash -c "curl -s https://raw.githubusercontent.com/$GITHUB_REPO/main/install/lxc/setup.sh > /root/setup.sh && chmod +x /root/setup.sh && bash /root/setup.sh"
