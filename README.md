## BV Leningen App
Een complete applicatie voor het beheren van leningen in uw BV, inclusief betaling tracking, jaaroverzichten en dashboard visualisaties.

## Gemakkelijke installatie op Proxmox

U kunt de applicatie eenvoudig installeren in een nieuwe Alpine Linux LXC container op Proxmox met het volgende commando:

```bash
wget -O - https://raw.githubusercontent.com/jeroenhonig/bv-leningen-app/main/install/proxmox/create-lxc.sh | bash
```
Dit script downloadt en installeert automatisch:
Een nieuwe Alpine Linux LXC container
PostgreSQL database
Node.js backend
React frontend
Nginx webserver
Automatische backups

Installatie-opties
Voor geavanceerde opties kunt u parameters meegeven:
```bash
wget -O - https://raw.githubusercontent.com/jeroenhonig/bv-leningen-app/main/install/proxmox/create-lxc.sh | bash -s -- [CTID] [HOSTNAME] [MEMORY] [DISK] [CORES] [IP_CONFIG] [BRIDGE]
```
Bijvoorbeeld:
```bash
# Aangepaste container ID 123, hostname 'loans', 1GB RAM, 10GB schijf, 2 cores
wget -O - https://raw.githubusercontent.com/jeroenhonig/bv-leningen-app/main/install/proxmox/create-lxc.sh | bash -s -- 123 loans 1024 10 2 dhcp
```
## Updates
Om de applicatie bij te werken naar de nieuwste versie:
```bash
wget -O - https://raw.githubusercontent.com/jeroenhonig/bv-leningen-app/main/install/lxc/update.sh | ash
```

## Functionaliteiten
- Overzicht van alle leningen
- Toevoegen/bewerken/verwijderen van leningen
- Registreren van betalingen
- Jaaroverzichten (handig voor de fiscus)
- Dashboard met grafieken en statistieken
- Automatische backups

## Licentie
Dit project is gelicenseerd onder de MIT-licentie - zie het LICENSE bestand voor details.
