#!/usr/bin/env bash
# =====================================================================
#  agrigeek-hotspot.sh
#  Digital Farming School - AgriGeek Hotspot (version Linux / NetworkManager)
#  Équivalent de src/Configurer-DFS.ps1 pour Manjaro / Arch (i3 ou autre).
#
#  1. Vérifie le lien Ethernet (corrige les coupures : EEE désactivé, puis 100 Mb/s)
#  2. Configure la carte Ethernet en IP fixe 172.20.0.xx (xx demandé ou choisi automatiquement)
#     Masque 255.255.255.0 - Passerelle 172.20.0.1 - DNS 8.8.8.8 / 1.1.1.1
#  3. Teste la connexion Internet (passerelle, DNS, web) via l'Ethernet
#  4. Crée le point d'accès Wi-Fi MY-DFS-HOTSPOT (partage NetworkManager = ICS de Windows)
#  5. Ouvre une page web locale (QR code + identifiants) dans le navigateur
#
#  Utilisation :
#    agrigeek-hotspot.sh                 configuration complète (interactive)
#    agrigeek-hotspot.sh --auto          choisit automatiquement un numéro libre
#    agrigeek-hotspot.sh --ip 42         utilise 172.20.0.42
#    agrigeek-hotspot.sh --repair        relance le point d'accès et répare le partage (sans toucher à l'IP)
#    agrigeek-hotspot.sh --page          rouvre seulement la page web locale
#    agrigeek-hotspot.sh --stop          arrête le point d'accès (le Wi-Fi se reconnecte à vos réseaux)
#    agrigeek-hotspot.sh --reset         remet la carte Ethernet en DHCP et arrête le point d'accès
#  Options : --yes (aucune question) --no-hotspot (Ethernet seulement) --no-web (pas de page)
# =====================================================================

set -u

# ===================== PARAMÈTRES =====================
GATEWAY='172.20.0.1'
NET_PREFIX='172.20.0.'
PREFIX_LEN=24                          # = 255.255.255.0
DNS_SERVERS='8.8.8.8 1.1.1.1'
HOTSPOT_SSID='MY-DFS-HOTSPOT'
HOTSPOT_PASS='123DFSIFIW'
HOTSPOT_IP='192.168.137.1'             # même sous-réseau que le partage Windows
WEB_PORT=8080
ETH_CON='DFS-Ethernet'                 # profil NetworkManager de l'Ethernet DFS
HS_CON='DFS-Hotspot'                   # profil NetworkManager du point d'accès
AUTO_FIRST=200                         # --auto : premier numéro essayé (puis 201... 254, 2... 199)
# ======================================================

SCRIPT_DIR=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/agrigeek-hotspot"
PYTHON=/usr/bin/python3; [ -x "$PYTHON" ] || PYTHON=python3

if [ -t 1 ]; then
    C_CYAN=$'\e[36m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_RED=$'\e[31m'
    C_BLUE=$'\e[34m'; C_GRAY=$'\e[90m'; C_RESET=$'\e[0m'
else
    C_CYAN=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_BLUE=''; C_GRAY=''; C_RESET=''
fi
step() { printf '\n%s==> %s%s\n' "$C_CYAN" "$*" "$C_RESET"; }
ok()   { printf '    %s[OK] %s%s\n' "$C_GREEN" "$*" "$C_RESET"; }
warn() { printf '    %s[!]  %s%s\n' "$C_YELLOW" "$*" "$C_RESET"; }
err()  { printf '    %s[X]  %s%s\n' "$C_RED" "$*" "$C_RESET"; }
note() { printf '    %s%s%s\n' "$C_GRAY" "$*" "$C_RESET"; }

MODE=full; DEVICE_NUM=''; AUTO=0; YES=0; NO_WEB=0; NO_HOTSPOT=0

usage() { sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

interactive() { [ -t 0 ] && [ "$YES" -eq 0 ]; }

# Équivalent de Stop-WithPause : pause seulement quand lancé depuis un raccourci (fenêtre qui se ferme)
pause_exit() {
    if [ "${AGRIGEEK_PAUSE:-0}" = 1 ] && [ -t 0 ]; then
        echo; read -rp 'Appuyez sur Entrée pour fermer' _
    fi
    exit "$1"
}
die() { err "$*"; pause_exit 1; }

con_exists() { nmcli -g NAME connection show | grep -qxF -- "$1"; }
con_active() { [ "$(nmcli -g GENERAL.STATE connection show "$1" 2>/dev/null)" = activated ]; }

# ---------- Arguments ----------
while [ $# -gt 0 ]; do
    case "$1" in
        --reset|-Reset)   MODE=reset ;;
        --repair|-Repair) MODE=repair ;;
        --stop)           MODE=stop ;;
        --page)           MODE=page ;;
        --ip)             DEVICE_NUM="${2:-}"; shift ;;
        --ip=*)           DEVICE_NUM="${1#*=}" ;;
        --auto)           AUTO=1 ;;
        --yes|-y)         YES=1 ;;
        --no-web)         NO_WEB=1 ;;
        --no-hotspot)     NO_HOTSPOT=1 ;;
        -h|--help)        usage; exit 0 ;;
        *) err "Option inconnue : $1"; usage; exit 2 ;;
    esac
    shift
done

valid_num() { [[ "$1" =~ ^[0-9]{1,3}$ ]] && [ "$1" -ge 2 ] && [ "$1" -le 254 ]; }
if [ -n "$DEVICE_NUM" ] && ! valid_num "$DEVICE_NUM"; then
    err "--ip $DEVICE_NUM invalide : entrez un nombre entre 2 et 254 (1 = passerelle)."; exit 2
fi

for c in nmcli ip ping curl; do
    command -v "$c" >/dev/null || { err "Commande « $c » introuvable."; exit 1; }
done

printf '%s' "$C_BLUE"
echo '  ____  _____ ____  '
echo ' |  _ \|  ___/ ___| '
echo ' | | | | |_  \___ \ '
printf '%s' "$C_GREEN"
echo ' | |_| |  _|  ___) |'
echo ' |____/|_|   |____/   AgriGeek Hotspot (Linux)'
printf '%s\n' "$C_RESET"

# =====================================================================
# 1. CARTE ETHERNET
# =====================================================================
ETH=''; WIFI=''

select_ethernet() {
    local all=() up=() list=() d t i c
    while IFS=: read -r d t; do
        # seulement les cartes physiques (exclut veth, ponts Docker...)
        [ "$t" = ethernet ] && [ -e "/sys/class/net/$d/device" ] && all+=("$d")
    done < <(nmcli -t -f DEVICE,TYPE device)
    if [ ${#all[@]} -eq 0 ]; then err 'Aucune carte Ethernet physique détectée sur cette machine.'; return 1; fi
    # une seule carte : la vérification du lien (check_link) dira si le câble pose problème
    if [ ${#all[@]} -eq 1 ]; then ETH=${all[0]}; return 0; fi

    for d in "${all[@]}"; do
        [ "$(cat "/sys/class/net/$d/carrier" 2>/dev/null)" = 1 ] && up+=("$d")
    done
    if [ ${#up[@]} -eq 0 ]; then
        warn 'Aucune carte Ethernet connectée : vérifiez que le câble réseau est branché.'
        list=("${all[@]}")
    else
        list=("${up[@]}")
    fi
    if [ ${#list[@]} -eq 1 ]; then ETH=${list[0]}; return 0; fi

    echo '    Plusieurs cartes Ethernet trouvées :'
    for i in "${!list[@]}"; do
        printf '      [%d] %s - %s\n' $((i + 1)) "${list[$i]}" "$(eth_desc "${list[$i]}")"
    done
    if ! interactive; then ETH=${list[0]}; warn "Choix automatique : $ETH"; return 0; fi
    while :; do
        read -rp '    Numéro de la carte à configurer : ' c
        if [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -ge 1 ] && [ "$c" -le ${#list[@]} ]; then
            ETH=${list[$((c - 1))]}; return 0
        fi
    done
}

eth_desc() {
    nmcli -g GENERAL.VENDOR,GENERAL.PRODUCT device show "$1" 2>/dev/null | paste -sd' ' -
}

eth_ip() { nmcli -g IP4.ADDRESS device show "$ETH" 2>/dev/null | head -n1 | cut -d/ -f1; }

# Profil NetworkManager dédié (n'écrase pas les autres profils filaires)
ensure_eth_profile() {
    if con_exists "$ETH_CON"; then
        nmcli connection modify "$ETH_CON" connection.interface-name "$ETH" ethtool.eee-enabled off \
            connection.autoconnect yes connection.autoconnect-priority 50
    else
        # sans IP pour l'instant ; autoconnect + priorité 50 : NetworkManager le reprend
        # après chaque micro-coupure au lieu de rebasculer sur un autre profil filaire
        nmcli connection add type ethernet con-name "$ETH_CON" ifname "$ETH" \
            ipv4.method disabled ipv6.method disabled \
            connection.autoconnect yes connection.autoconnect-priority 50 \
            ethtool.eee-enabled off >/dev/null
    fi
}

# Profil créé par ce script mais jamais configuré (pas d'IP) : on le retire pour libérer la carte
drop_unconfigured_profile() {
    if con_exists "$ETH_CON" && [ "$(nmcli -g ipv4.method connection show "$ETH_CON")" = disabled ]; then
        nmcli connection delete "$ETH_CON" >/dev/null 2>&1
    fi
}

wait_carrier() {   # $1 secondes max
    local i
    for ((i = 0; i < $1 * 5; i++)); do
        [ "$(cat "/sys/class/net/$ETH/carrier" 2>/dev/null)" = 1 ] && return 0
        sleep 0.2
    done
    return 1
}

# NetworkManager refuse d'activer un profil sans porteuse : on attend le lien et on réessaie
eth_up() {
    local t
    for t in 1 2 3 4; do
        wait_carrier 10 || continue
        nmcli -w "${1:-30}" connection up "$ETH_CON" >/dev/null 2>&1 && return 0
        sleep 1
    done
    return 1
}

# Applique les réglages du lien : « reapply » si le profil est déjà actif (sans couper l'IP), sinon activation
eth_apply_link() {
    if con_active "$ETH_CON"; then
        nmcli device reapply "$ETH" >/dev/null 2>&1 || eth_up 20
    else
        eth_up 20
    fi
}

carrier_of() { cat "/sys/class/net/$ETH/carrier" 2>/dev/null || echo 0; }
changes_of() { cat "/sys/class/net/$ETH/carrier_changes" 2>/dev/null || echo 0; }
FLAPS=0
sample_link() {   # $1 secondes -> FLAPS = nombre de changements d'état du lien
    local a b
    a=$(changes_of); sleep "$1"; b=$(changes_of)
    FLAPS=$((b - a))
}

# Les cartes Realtek (r8169) perdent souvent le lien avec l'économie d'énergie EEE ou un câble abîmé
check_link() {
    step "Vérification du lien Ethernet ($ETH)"
    ensure_eth_profile || { err "Impossible de créer le profil « $ETH_CON »."; return 1; }
    eth_apply_link
    sleep 3
    sample_link 8
    if [ "$FLAPS" -eq 0 ] && [ "$(carrier_of)" = 1 ]; then
        ok "Lien stable - $(cat "/sys/class/net/$ETH/speed" 2>/dev/null) Mb/s"
        return 0
    fi
    if [ "$FLAPS" -eq 0 ]; then
        err "Aucun signal sur $ETH : câble débranché, switch éteint ou prise morte."
        return 1
    fi
    warn "Lien instable : $FLAPS coupures en 8 s (économie d'énergie EEE déjà désactivée)."
    warn 'Limitation du lien à 100 Mb/s full-duplex...'
    nmcli connection modify "$ETH_CON" 802-3-ethernet.auto-negotiate yes \
        802-3-ethernet.speed 100 802-3-ethernet.duplex full
    eth_apply_link
    sleep 3
    sample_link 10
    if [ "$FLAPS" -le 1 ] && [ "$(carrier_of)" = 1 ]; then
        ok 'Lien stabilisé à 100 Mb/s.'
        return 0
    fi
    err "Lien toujours instable ($FLAPS coupures en 10 s) : problème physique."
    warn 'Changez le câble réseau ou essayez une autre prise du switch, puis relancez.'
    return 1
}

current_num() {   # numéro déjà enregistré dans le profil, s'il existe
    local a
    a=$(nmcli -g ipv4.addresses connection show "$ETH_CON" 2>/dev/null | cut -d, -f1)
    a=${a%%/*}
    [[ "$a" == "$NET_PREFIX"* ]] && valid_num "${a#"$NET_PREFIX"}" && echo "${a#"$NET_PREFIX"}"
}

# Applique 172.20.0.$1 ; NetworkManager vérifie que l'adresse est libre (ACD = détection de conflit)
# Retour : 0 OK, 2 adresse déjà utilisée, 1 autre erreur
apply_ip() {
    local ip="$NET_PREFIX$1" since
    since=$(date '+%Y-%m-%d %H:%M:%S')
    nmcli connection modify "$ETH_CON" \
        ipv4.method manual ipv4.addresses "$ip/$PREFIX_LEN" ipv4.gateway "$GATEWAY" \
        ipv4.dns "$DNS_SERVERS" ipv4.ignore-auto-dns yes ipv4.dad-timeout 3000 \
        ipv4.route-metric 50 ipv6.method disabled \
        connection.autoconnect yes connection.autoconnect-priority 50 || return 1
    if eth_up 45 && ip -4 -o addr show dev "$ETH" | grep -qF " $ip/"; then
        return 0
    fi
    if journalctl -u NetworkManager --since "$since" --no-pager -q 2>/dev/null |
       grep -iF "$ip" | grep -qiE 'already in use|conflict'; then
        return 2
    fi
    return 1
}

read_device_num() {
    local def v
    def=$(current_num)
    while :; do
        if [ -n "$def" ]; then
            read -rp "$(printf '\n    Numéro de cet appareil sur le réseau (2 à 254, Entrée = %s) -> %sxx : ' "$def" "$NET_PREFIX")" v
            v=${v:-$def}
        else
            read -rp "$(printf '\n    Numéro de cet appareil sur le réseau (2 à 254, Entrée = automatique) -> %sxx : ' "$NET_PREFIX")" v
            [ -z "$v" ] && { echo auto; return; }
        fi
        if valid_num "$v"; then echo "$v"; return; fi
        warn 'Valeur invalide : entrez un nombre entre 2 et 254 (1 = passerelle).' >&2
    done
}

# --auto : essaie le numéro déjà enregistré, puis 200..254, puis 2..199
auto_pick() {
    local n a cur
    cur=$(current_num)
    for n in $cur $(seq "$AUTO_FIRST" 254) $(seq 2 $((AUTO_FIRST - 1))); do
        if interactive; then
            read -rp "    Utiliser $NET_PREFIX$n ? [O/n] " a
            [[ "$a" =~ ^[nN] ]] && continue
        fi
        step "Configuration de $ETH : $NET_PREFIX$n / 255.255.255.0 - passerelle $GATEWAY"
        apply_ip "$n"
        case $? in
            0) DEVICE_NUM=$n; return 0 ;;
            2) warn "$NET_PREFIX$n est déjà utilisée par un autre appareil, essai suivant." ;;
            *) err "Impossible d'appliquer $NET_PREFIX$n (lien Ethernet coupé ?)."; return 1 ;;
        esac
    done
    err 'Aucune adresse libre trouvée.'; return 1
}

# =====================================================================
# 2. TEST INTERNET (forcé sur l'Ethernet pour que le Wi-Fi ne fausse pas le résultat)
# =====================================================================
R_GW=0; R_DNS=0; R_WEB=0
test_internet() {
    local try dns1=${DNS_SERVERS%% *}
    for try in 1 2 3; do
        R_GW=0; R_DNS=0; R_WEB=0
        ping -I "$ETH" -c 2 -W 2 -q "$GATEWAY" >/dev/null 2>&1 && R_GW=1
        if command -v drill >/dev/null; then
            drill -Q www.google.com @"$dns1" A 2>/dev/null | grep -qE '^[0-9.]+$' && R_DNS=1
        else
            getent ahostsv4 www.google.com >/dev/null && R_DNS=1
        fi
        curl -s --interface "$ETH" -m 8 http://nmcheck.gnome.org/check_network_status.txt 2>/dev/null |
            grep -q 'NetworkManager is online' && R_WEB=1
        [ "$R_WEB" = 1 ] && break
        if [ "$try" -lt 3 ]; then note "Tentative $try échouée, nouvel essai dans 5 s..."; sleep 5; fi
    done
}

# =====================================================================
# 3. POINT D'ACCÈS WI-FI (NetworkManager, mode « shared » = partage de connexion)
# =====================================================================
select_wifi() {
    WIFI=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2 == "wifi" { print $1; exit }')
    if [ -z "$WIFI" ]; then err 'Aucune carte Wi-Fi détectée.'; return 1; fi
    if [ "$(nmcli radio wifi)" != enabled ]; then
        nmcli radio wifi on && warn 'Wi-Fi activé (il était désactivé).'
        sleep 2
    fi
    if command -v iw >/dev/null && ! iw list 2>/dev/null | grep -qE '^\s+\* AP$'; then
        err "La carte Wi-Fi « $WIFI » ne permet pas de créer un point d'accès (mode AP)."; return 1
    fi
    if ! command -v dnsmasq >/dev/null; then
        err 'dnsmasq est nécessaire au partage NetworkManager : sudo pacman -S dnsmasq'; return 1
    fi
    return 0
}

ufw_active()    { systemctl is-active -q ufw 2>/dev/null; }
docker_active() { systemctl is-active -q docker 2>/dev/null; }

print_fw_cmds() {
    if ufw_active; then
        echo "sudo ufw allow in on $WIFI to any port 67 proto udp comment AgriGeek-DHCP"
        echo "sudo ufw allow in on $WIFI to any port 53 comment AgriGeek-DNS"
        echo "sudo ufw route allow in on $WIFI out on $ETH comment AgriGeek-partage"
    elif docker_active; then
        echo "sudo iptables -I DOCKER-USER -i $WIFI -o $ETH -j ACCEPT"
        echo "sudo iptables -I DOCKER-USER -i $ETH -o $WIFI -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
    fi
}

apply_fw_rules() {
    if ufw_active; then
        sudo ufw allow in on "$WIFI" to any port 67 proto udp comment AgriGeek-DHCP >/dev/null &&
        sudo ufw allow in on "$WIFI" to any port 53 comment AgriGeek-DNS >/dev/null &&
        sudo ufw route allow in on "$WIFI" out on "$ETH" comment AgriGeek-partage >/dev/null
    else   # Docker seul : sa politique FORWARD DROP bloque aussi le partage (règles non persistantes)
        { sudo iptables -C DOCKER-USER -i "$WIFI" -o "$ETH" -j ACCEPT 2>/dev/null ||
          sudo iptables -I DOCKER-USER -i "$WIFI" -o "$ETH" -j ACCEPT; } &&
        { sudo iptables -C DOCKER-USER -i "$ETH" -o "$WIFI" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null ||
          sudo iptables -I DOCKER-USER -i "$ETH" -o "$WIFI" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; }
    fi
}

# ufw (et Docker) bloquent par défaut le DHCP/DNS du point d'accès et le routage vers l'Ethernet
setup_firewall() {   # $1 = 1 pour forcer
    local marker="$CONF_DIR/firewall-$WIFI-$ETH.ok"
    if ! ufw_active && ! docker_active; then ok 'Aucun pare-feu à adapter.'; return 0; fi
    if [ "${1:-0}" -eq 0 ] && ufw_active && [ -f "$marker" ]; then
        ok 'Règles du pare-feu (ufw) déjà en place pour le partage.'; return 0
    fi
    if sudo -n true 2>/dev/null || [ -t 0 ]; then
        warn "Mot de passe administrateur demandé pour ouvrir le pare-feu au point d'accès."
        if apply_fw_rules; then
            ok "Pare-feu : DHCP, DNS et routage $WIFI -> $ETH autorisés."
            ufw_active && { mkdir -p "$CONF_DIR"; touch "$marker"; }
            return 0
        fi
        err 'Les règles du pare-feu n'"'"'ont pas pu être ajoutées.'
    else
        err "Droits administrateur nécessaires pour le pare-feu (aucun terminal pour le mot de passe)."
    fi
    warn "Sans ces règles, les téléphones n'auront pas Internet. Lancez dans un terminal :"
    print_fw_cmds | sed 's/^/        /'
    return 1
}

ensure_hotspot_profile() {
    local args=(
        connection.interface-name "$WIFI" connection.autoconnect no
        802-11-wireless.ssid "$HOTSPOT_SSID" 802-11-wireless.mode ap
        802-11-wireless.band bg 802-11-wireless.powersave 2
        ipv4.method shared ipv4.addresses "$HOTSPOT_IP/24" ipv6.method disabled
        wifi-sec.key-mgmt wpa-psk wifi-sec.proto rsn
        wifi-sec.pairwise ccmp wifi-sec.group ccmp wifi-sec.psk "$HOTSPOT_PASS"
    )
    if con_exists "$HS_CON"; then
        nmcli connection modify "$HS_CON" "${args[@]}"
    else
        nmcli connection add type wifi con-name "$HS_CON" ifname "$WIFI" ssid "$HOTSPOT_SSID" "${args[@]}" >/dev/null
    fi
}

test_hotspot_sharing() {
    if ip -4 -o addr show dev "$WIFI" | grep -qF " $HOTSPOT_IP/"; then
        ok "Carte du point d'accès « $WIFI » : $HOTSPOT_IP"
    else
        err "La carte du point d'accès n'a pas l'adresse $HOTSPOT_IP. Les appareils ne recevront pas d'adresse valide."
    fi
    if [ "$(cat /proc/sys/net/ipv4/ip_forward)" = 1 ]; then
        ok 'Routage IPv4 actif.'
    else
        err "Routage IPv4 désactivé (net.ipv4.ip_forward = 0) : pas d'Internet pour les appareils."
    fi
    if command -v drill >/dev/null; then
        if drill -Q www.google.com @"$HOTSPOT_IP" A 2>/dev/null | grep -qE '^[0-9.]+$'; then
            ok "Relais DNS du point d'accès opérationnel."
        else
            warn "Le relais DNS du point d'accès ($HOTSPOT_IP) ne répond pas."
        fi
    fi
}

start_hotspot() {   # $1 = 1 pour forcer le pare-feu et redémarrer le point d'accès
    local force=${1:-0} out
    select_wifi || return 1
    setup_firewall "$force"
    ensure_hotspot_profile || { err "Impossible de créer le profil « $HS_CON »."; return 1; }
    if [ "$force" -eq 1 ] && con_active "$HS_CON"; then
        nmcli connection down "$HS_CON" >/dev/null 2>&1; sleep 2
    fi
    if ! out=$(nmcli -w 60 connection up "$HS_CON" 2>&1); then
        err "Échec du démarrage du point d'accès : $out"
        return 1
    fi
    sleep 2
    test_hotspot_sharing
    return 0
}

# =====================================================================
# 4. PAGE WEB LOCALE (QR code + état)
# =====================================================================
start_web() {
    local cfg
    if [ ! -x "$PYTHON" ] && ! command -v "$PYTHON" >/dev/null; then
        warn 'python3 introuvable : page web non lancée.'; return 1
    fi
    [ -z "$WIFI" ] && WIFI=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2 == "wifi" { print $1; exit }')
    cfg=$("$PYTHON" -I -c 'import json, sys; a = sys.argv[1:]; print(json.dumps(dict(zip(a[::2], a[1::2])), ensure_ascii=False))' \
        ssid "$HOTSPOT_SSID" password "$HOTSPOT_PASS" ethernet "$(eth_ip)" gateway "$GATEWAY" \
        dns "${DNS_SERVERS// / · }" hotspotIp "$HOTSPOT_IP" adapter "$ETH")
    exec "$PYTHON" -I "$SCRIPT_DIR/web/server.py" --config "$cfg" --port "$WEB_PORT" \
        --hotspot-con "$HS_CON" --wifi-dev "$WIFI" --open
}

# =====================================================================
# PROGRAMME PRINCIPAL
# =====================================================================
step 'Recherche de la carte Ethernet'
select_ethernet || pause_exit 1
ok "$ETH - $(eth_desc "$ETH")"

case "$MODE" in
    reset)
        step 'Retour de la carte Ethernet en mode automatique (DHCP)'
        if con_active "$HS_CON"; then nmcli connection down "$HS_CON" >/dev/null && ok "Point d'accès arrêté."; fi
        if con_exists "$ETH_CON"; then nmcli connection delete "$ETH_CON" >/dev/null && ok "Profil « $ETH_CON » supprimé."; fi
        dhcp=''
        while IFS=: read -r name type; do
            [ "$type" = 802-3-ethernet ] || [ "$type" = ethernet ] || continue
            iface=$(nmcli -g connection.interface-name connection show "$name")
            if [ "$(nmcli -g ipv4.method connection show "$name")" = auto ] && { [ -z "$iface" ] || [ "$iface" = "$ETH" ]; }; then
                dhcp=$name; break
            fi
        done < <(nmcli -t -f NAME,TYPE connection show)
        if [ -z "$dhcp" ]; then
            dhcp='Wired DHCP'
            nmcli connection add type ethernet con-name "$dhcp" ifname "$ETH" ipv4.method auto >/dev/null
        fi
        nmcli -w 30 connection up "$dhcp" >/dev/null 2>&1 || warn "Profil « $dhcp » pas encore actif (câble ?)."
        ok 'Configuration automatique rétablie.'
        pause_exit 0 ;;
    stop)
        step "Arrêt du point d'accès « $HOTSPOT_SSID »"
        nmcli connection down "$HS_CON" >/dev/null 2>&1
        ok "Point d'accès arrêté. Le Wi-Fi se reconnecte à vos réseaux habituels."
        pause_exit 0 ;;
    repair)
        step "Relance du point d'accès et réparation du partage Internet"
        if start_hotspot 1; then
            ok "Point d'accès « $HOTSPOT_SSID » actif. Déconnectez puis reconnectez les téléphones."
        fi
        pause_exit 0 ;;
    page)
        start_web; pause_exit 1 ;;
esac

# ---- Configuration complète ----
if ! check_link; then
    a=''
    interactive && read -rp "$(printf '\n    Continuer quand même ? [o/N] ')" a
    if [[ ! "$a" =~ ^[oOyY] ]]; then drop_unconfigured_profile; pause_exit 1; fi
fi

connected=0
while [ "$connected" -eq 0 ]; do
    n=$DEVICE_NUM
    if [ -z "$n" ] && [ "$AUTO" -eq 0 ]; then
        if interactive; then n=$(read_device_num); else n=auto; fi
    fi
    if [ -z "$n" ] || [ "$n" = auto ]; then
        auto_pick || pause_exit 1
        n=$DEVICE_NUM
    else
        step "Configuration de $ETH : $NET_PREFIX$n / 255.255.255.0 - passerelle $GATEWAY"
        apply_ip "$n"
        case $? in
            0) ;;
            2) err "L'adresse $NET_PREFIX$n est déjà utilisée par un autre appareil. Choisissez un autre numéro."
               DEVICE_NUM=''; interactive || pause_exit 1; continue ;;
            *) err "Impossible d'appliquer $NET_PREFIX$n (lien Ethernet coupé ?)."
               DEVICE_NUM=''; interactive || pause_exit 1; continue ;;
        esac
    fi
    ip_addr="$NET_PREFIX$n"
    ok "IP $ip_addr - DNS ${DNS_SERVERS// /, }"

    step 'Test de la connexion Internet'
    test_internet
    [ "$R_GW" = 1 ]  && ok 'Passerelle joignable' || err 'Passerelle injoignable'
    [ "$R_DNS" = 1 ] && ok 'DNS joignable'        || err 'DNS injoignable'
    [ "$R_WEB" = 1 ] && ok 'Web joignable'        || err 'Web injoignable'

    if [ "$R_WEB" = 1 ]; then
        connected=1
    else
        if [ "$R_GW" = 0 ]; then warn 'La passerelle ne répond pas : vérifiez le câble ou le switch.'
        elif [ "$R_DNS" = 0 ]; then warn 'La passerelle répond mais pas le DNS : le réseau bloque peut-être 8.8.8.8 / 1.1.1.1.'
        fi
        interactive || pause_exit 1
        read -rp "$(printf '\n    [R] Réessayer avec un autre numéro   [Q] Quitter : ')" a
        [[ "$a" =~ ^[qQ] ]] && pause_exit 1
        DEVICE_NUM=''; AUTO=0
    fi
done
ok 'Internet fonctionne.'

if [ "$NO_HOTSPOT" -eq 1 ]; then pause_exit 0; fi

step "Création du point d'accès Wi-Fi « $HOTSPOT_SSID »"
start_hotspot 0 || pause_exit 1
ok "Point d'accès actif - mot de passe : $HOTSPOT_PASS"
warn "Nombre maximum d'appareils fixé par le pilote Wi-Fi (non réglable comme sous Windows)."

if [ "$NO_WEB" -eq 1 ]; then pause_exit 0; fi
start_web
pause_exit 1
