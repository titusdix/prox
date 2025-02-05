#!/bin/sh

export PUBIP=192.168.1.46
export SSHPORT=3615

# -----------
# VARIABLES
# -----------

## Le pont Proxmox qui gère l'IP publique (ou l'autoroute pour internet, en gros)
PrxPubVBR="vmbr0"
## Le pont Proxmox pour VmWanNET (le côté WAN de PFSense, ou l’entrée pour la tempête réseau)
PrxVmWanVBR="vmbr1"
## Le pont Proxmox pour PrivNET (le côté LAN de PFSense, alias « tranquille dans le salon »)
PrxVmPrivVBR="vmbr2"

## Le réseau/Masque du VmWanNET (c’est là que tout s’embrouille)
VmWanNET="10.10.10.0/30"
## Le réseau/Masque du PrivNET (la zone chill pour les appareils)
PrivNET="192.168.10.0/24"
## Le réseau/Masque du VpnNET (le tunnel secret de James Bond)
#VpnNET="192.168.30.0/24"

## Adresse IP publique (celle que tout le monde stalk en ligne)
PublicIP="${PUBIP}"
## Adresse IP Proxmox dans le même réseau que PFSense WAN (la pote de PFSense WAN)
ProxVmWanIP="10.10.10.1"
## Adresse IP Proxmox dans le réseau des VMs (la babysitter des VMs)
ProxVmPrivIP="192.168.10.1"
## L’IP de PFSense côté firewall (le garde du corps officiel)
PfsVmWanIP="10.10.10.2"

## ASTUCE DE SIOUX
##iptables -A OUTPUT -p tcp -o vmbr1 -j LOG # « Attrape-moi si tu peux » pour les paquets sortants

# ---------------------
# TOUT NETTOYER & STOPPER L’IPV6
# ---------------------

### Supprime toutes les règles existantes. RIP.
iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -X
### Ici, on dit gentiment à l’IPv6 : « casse-toi, t’es pas invité à la fête ».

ip6tables -P INPUT DROP
ip6tables -P OUTPUT DROP
ip6tables -P FORWARD DROP
ip6tables -A INPUT -i lo -j ACCEPT
ip6tables -A OUTPUT -o lo -j ACCEPT
ip6tables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
ip6tables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# ------------
# RÈGLES GLOBALES
# ------------

# Autorise localhost parce que « toi, t’es cool »
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
# On ne tue pas les connexions déjà en place. On n’est pas des sauvages !
iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
# Autorise le ping (parce que c’est gentil de répondre « coucou »). Commentez pour devenir antisocial.
iptables -A INPUT -p icmp --icmp-type 8 -m conntrack --ctstate NEW -j ACCEPT

# --------------
# POLITIQUE PAR DÉFAUT
# --------------

### Bloque tout parce que... pourquoi pas ?
iptables -P OUTPUT DROP
iptables -P INPUT DROP
iptables -P FORWARD DROP

# ------
# CHAÎNES
# ------
## trie le bordel en gros 
### Création des chaînes (non, pas celles pour le vélo)
iptables -N TCP
iptables -N UDP

# UDP = ACCEPTE / LANCE DANS LA CHAÎNE (parce que UDP est cool)
iptables -A INPUT -p udp -m conntrack --ctstate NEW -j UDP
# TCP = ACCEPTE / LANCE DANS LA CHAÎNE (TCP aime les règles)
iptables -A INPUT -p tcp --syn -m conntrack --ctstate NEW -j TCP

# --------------------
# RÈGLES POUR PrxPubVBR
# --------------------

### RÈGLES D'ENTRÉE
# -----------------

# Autorise SSH parce que c’est pratique de se connecter à distance
iptables -A TCP -i $PrxPubVBR -d $PublicIP -p tcp --dport ${SSHPORT} -j ACCEPT

# Autorise l’interface web Proxmox, mais seulement si vous commentez la ligne.
iptables -A TCP -i $PrxPubVBR -d $PublicIP -p tcp --dport 8006 -j ACCEPT

iptables -A TCP -i $PrxVmWanVBR -d $ProxVmWanIP -p tcp --dport 8006 -j ACCEPT

### RÈGLES DE SORTIE
# ------------------

# Autorise le ping pour dire « coucou, je suis là ! »
iptables -A OUTPUT -p icmp -j ACCEPT

### Proxmox en CLIENT
# Autorise HTTP/HTTPS parce que la navigation, c’est la vie
iptables -A OUTPUT -o $PrxPubVBR -s $PublicIP -p tcp --dport 80 -j ACCEPT
iptables -A OUTPUT -o $PrxPubVBR -s $PublicIP -p tcp --dport 443 -j ACCEPT
# Autorise DNS parce que sans DNS, c’est la galère
iptables -A OUTPUT -o $PrxPubVBR -s $PublicIP -p udp --dport 53 -j ACCEPT

### Proxmox en SERVEUR
# Autorise SSH (parce que c’est toujours pratique)
iptables -A OUTPUT -o $PrxPubVBR -s $PublicIP -p tcp --sport ${SSHPORT} -j ACCEPT
# Autorise l’interface web Proxmox (si vous décidez de la décommenter)
iptables -A OUTPUT -o $PrxPubVBR -s $PublicIP -p tcp --sport 8006 -j ACCEPT

### RÈGLES DE FORWARDING
# ----------------------

### Redirige (NAT) le trafic depuis Internet vers PFSense WAN, sauf SSH et 8006 (on ne rigole pas avec ça)
iptables -A PREROUTING -t nat -i $PrxPubVBR -p tcp --match multiport ! --dports ${SSHPORT},8006 -j DNAT --to $PfsVm>
# Tout le trafic UDP vers PFSense WAN, parce qu’il ne mérite pas d’être discriminé
iptables -A PREROUTING -t nat -i $PrxPubVBR -p udp -j DNAT --to $PfsVmWanIP

# Autorise le forwarding vers l’interface WAN de PFSense
iptables -A FORWARD -i $PrxPubVBR -d $PfsVmWanIP -o $PrxVmWanVBR -p tcp -j ACCEPT
iptables -A FORWARD -i $PrxPubVBR -d $PfsVmWanIP -o $PrxVmWanVBR -p udp -j ACCEPT

# Autorise le forwarding depuis le LAN (quand les appareils LAN veulent sortir)
iptables -A FORWARD -i $PrxVmWanVBR -s $VmWanNET -j ACCEPT

### MASQUERADE OBLIGATOIRE (alias « cache ta vraie IP »)
# Autorise le réseau WAN (PFSense) à utiliser l’adresse publique vmbr0 pour sortir
iptables -t nat -A POSTROUTING -s $VmWanNET -o $PrxPubVBR -j MASQUERADE

# --------------------
# RÈGLES POUR PrxVmWanVBR
# --------------------

### Autorise Proxmox à jouer les clients pour les VMs
iptables -A OUTPUT -o $PrxVmWanVBR -s $ProxVmWanIP -p tcp -j ACCEPT

