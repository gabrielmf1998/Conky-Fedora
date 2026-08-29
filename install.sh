#!/usr/bin/env bash
# Instalação por fonte, sem root, para distros sem pacote aqui.
#   ./install.sh            instala painel + tray e sobe
#   ./install.sh --remove   remove tudo o que o instalador criou
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$HOME/.config/conky/pride"
LIB="$HOME/.local/share/conky-fedora-panel"
BIN="$HOME/.local/bin/conky-panel-tray"
UNITDIR="$HOME/.config/systemd/user"
DESKTOP="$HOME/.local/share/applications/conky-panel-tray.desktop"

say()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!!\033[0m  %s\n' "$*"; }

if [[ ${1:-} == --remove ]]; then
    say "parando e removendo"
    systemctl --user disable --now conky-panel-tray.service 2>/dev/null || true
    systemctl --user disable --now conky-fedora-panel.service 2>/dev/null || true
    for p in $(pgrep -x conky 2>/dev/null || true); do
        tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q "conky/pride" && kill "$p" || true
    done
    rm -rf "$LIB"
    rm -f "$BIN" "$DESKTOP" \
          "$UNITDIR/conky-fedora-panel.service" "$UNITDIR/conky-panel-tray.service" \
          "$HOME/.config/autostart/conky-pride.desktop"
    systemctl --user daemon-reload 2>/dev/null || true
    say "removido. A tua config em $CONF ficou, apague à mão se quiser."
    exit 0
fi

say "conferindo dependências"
command -v conky >/dev/null || { warn "falta o conky:  sudo dnf install conky"; exit 1; }
fc-list 2>/dev/null | grep -qi "Terminus (TTF)" ||
    warn "sem a fonte Terminus TTF o painel fica com o alinhamento torto"
python3 -c "import PySide6.QtWidgets" 2>/dev/null ||
    warn "sem PySide6 o painel funciona, mas o ícone de bandeja não"

say "instalando a config em $CONF"
mkdir -p "$CONF/scripts" "$LIB/conkytray" "$(dirname "$BIN")" "$UNITDIR" \
         "$(dirname "$DESKTOP")"
if [[ -f "$CONF/pride.conf" ]]; then
    say "já existe uma config sua — mantida intacta"
else
    install -m 0644 "$SRC/conky/pride.conf"   "$CONF/pride.conf"
    install -m 0755 "$SRC"/conky/scripts/*.sh "$CONF/scripts/"
fi
# cópia pristina, para o "Reset config" do tray ter de onde restaurar
install -d "$LIB/scripts"
install -m 0644 "$SRC/conky/pride.conf"    "$LIB/pride.conf"
install -m 0755 "$SRC"/conky/scripts/*.sh  "$LIB/scripts/"
install -m 0644 "$SRC/conky/60-rapl.rules" "$LIB/60-rapl.rules"
install -m 0644 "$SRC"/tray/conkytray/*.py "$LIB/conkytray/"
install -m 0644 "$SRC/assets/conky-panel-tray-256.png" "$LIB/icon.png"

cat > "$BIN" <<EOF
#!/bin/sh
export PYTHONPATH="$LIB\${PYTHONPATH:+:\$PYTHONPATH}"
exec python3 -m conkytray "\$@"
EOF
chmod 0755 "$BIN"

sed "s|/usr/bin/conky-panel-tray|$BIN|" "$SRC/systemd/conky-panel-tray.service" \
    > "$UNITDIR/conky-panel-tray.service"
cp "$SRC/systemd/conky-fedora-panel.service" "$UNITDIR/conky-fedora-panel.service"
sed -e "s|/usr/bin/conky-panel-tray|$BIN|" -e "s|^Icon=.*|Icon=$LIB/icon.png|" \
    "$SRC/systemd/conky-panel-tray.desktop" > "$DESKTOP"

say "ligando o painel e o tray"
rm -f "$HOME/.config/autostart/conky-pride.desktop"
systemctl --user daemon-reload
systemctl --user enable --now conky-fedora-panel.service
python3 -c "import PySide6.QtWidgets" 2>/dev/null &&
    systemctl --user enable --now conky-panel-tray.service || true

sleep 2
systemctl --user is-active --quiet conky-fedora-panel.service &&
    say "painel no ar" || warn "painel não subiu: journalctl --user -u conky-fedora-panel -n 30"

echo
echo "  ligar/desligar:  pelo menu do ícone na bandeja"
echo "  ou:              systemctl --user start|stop conky-fedora-panel"
echo "  editar:          \$EDITOR $CONF/pride.conf"
