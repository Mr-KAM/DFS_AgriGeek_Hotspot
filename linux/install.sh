#!/usr/bin/env bash
# install.sh - AgriGeek Hotspot (Linux)
# Équivalent des raccourcis créés par build/Construire-EXE.ps1 :
#   - commande « agrigeek-hotspot » dans ~/.local/bin
#   - lanceurs « AgriGeek Hotspot », « Réparer le partage Internet » et « Ethernet en DHCP »
#     dans ~/.local/share/applications (visibles dans i3-dmenu-desktop, rofi -show drun...)
# Aucun droit administrateur requis. N'édite pas la configuration i3.

set -u
DIR=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
ROOT=$(dirname "$DIR")
SCRIPT="$DIR/agrigeek-hotspot.sh"
BIN="$HOME/.local/bin"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"

mkdir -p "$BIN" "$APPS"
chmod +x "$SCRIPT" "$DIR/web/server.py"
ln -sf "$SCRIPT" "$BIN/agrigeek-hotspot"
echo "[OK] Commande : $BIN/agrigeek-hotspot"

desktop() {   # $1 fichier, $2 nom, $3 description, $4 options
    cat > "$APPS/$1" <<EOF
[Desktop Entry]
Type=Application
Name=$2
Comment=$3
Exec=env AGRIGEEK_PAUSE=1 "$SCRIPT" $4
Icon=$ROOT/assets/agrigeek.png
Terminal=true
Categories=Network;
EOF
    echo "[OK] Lanceur : $APPS/$1"
}
desktop agrigeek-hotspot.desktop "AgriGeek Hotspot" \
    "Ethernet DFS en IP fixe + point d'accès Wi-Fi avec QR code" ""
desktop agrigeek-hotspot-repair.desktop "Réparer le partage Internet" \
    "Relance le point d'accès AgriGeek sans toucher à l'IP" "--repair"
desktop agrigeek-hotspot-reset.desktop "AgriGeek - Ethernet en DHCP" \
    "Remet la carte Ethernet en automatique et arrête le point d'accès" "--reset"

command -v update-desktop-database >/dev/null && update-desktop-database "$APPS" 2>/dev/null

case ":$PATH:" in
    *":$BIN:"*) ;;
    *) echo "[!] $BIN n'est pas dans le PATH : ajoutez  export PATH=\"\$HOME/.local/bin:\$PATH\"  à ~/.zshrc" ;;
esac

cat <<EOF

Raccourci i3 facultatif (à ajouter à ~/.config/i3/config) :
    bindsym \$mod+Shift+h exec --no-startup-id i3-sensible-terminal -e env AGRIGEEK_PAUSE=1 agrigeek-hotspot
EOF
