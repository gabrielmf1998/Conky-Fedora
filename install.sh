#!/usr/bin/env bash
# Instalador do painel Conky Fedora.
#   ./install.sh            instala e sobe o painel
#   ./install.sh --remove   remove tudo o que o instalador criou
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.config/conky/pride"
AUTOSTART="$HOME/.config/autostart/conky-pride.desktop"
UDEV="/etc/udev/rules.d/60-rapl.rules"

say()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!!\033[0m  %s\n' "$*"; }

stop_panel() {
    local p
    for p in $(pgrep -x conky 2>/dev/null || true); do
        tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q "conky/pride" && kill "$p" || true
    done
    systemctl --user stop conky-pride 2>/dev/null || true
    systemctl --user reset-failed conky-pride 2>/dev/null || true
}

if [[ ${1:-} == --remove ]]; then
    say "parando o painel"
    stop_panel
    rm -f "$AUTOSTART"
    rm -rf "$DEST"
    rm -f "/tmp/.conky-pride."* "$HOME/.local/state/conky-pride/headset"
    say "removido. A regra udev do RAPL ficou em $UDEV — apague à mão se quiser:"
    echo "    sudo rm $UDEV && sudo udevadm control --reload-rules"
    exit 0
fi

# ── dependências ────────────────────────────────────────────
say "conferindo dependências"
missing=()
command -v conky >/dev/null || missing+=(conky)
fc-list 2>/dev/null | grep -qi "Terminus (TTF)" || missing+=(ax86-terminus-ttf-fonts)
command -v sensors >/dev/null || missing+=(lm_sensors)
if (( ${#missing[@]} )); then
    warn "faltando: ${missing[*]}"
    echo "    sudo dnf install ${missing[*]}"
    exit 1
fi
command -v nvidia-smi >/dev/null || warn "sem nvidia-smi: a seção GPU vai ficar vazia"

# ── arquivos ────────────────────────────────────────────────
say "instalando em $DEST"
stop_panel
mkdir -p "$DEST/scripts" "$HOME/.local/state/conky-pride"
install -m 0644 "$SRC/conky/pride.conf" "$DEST/pride.conf"
install -m 0755 "$SRC"/conky/scripts/*.sh "$DEST/scripts/"

# ── RAPL (consumo da CPU) ───────────────────────────────────
if [[ -r /sys/class/powercap/intel-rapl:0/energy_uj ]]; then
    say "RAPL já legível, pulando a regra udev"
else
    say "liberando os contadores de energia da CPU (precisa de root)"
    if sudo install -m 0644 "$SRC/conky/60-rapl.rules" "$UDEV" &&
       sudo udevadm control --reload-rules &&
       sudo chgrp -R wheel /sys/devices/virtual/powercap/intel-rapl 2>/dev/null &&
       sudo chmod -R g+rX /sys/devices/virtual/powercap/intel-rapl 2>/dev/null; then
        say "RAPL liberado para o grupo wheel"
    else
        warn "não consegui liberar o RAPL; o campo Power vai ficar vazio"
    fi
fi

# ── autostart ───────────────────────────────────────────────
say "criando autostart"
mkdir -p "$(dirname "$AUTOSTART")"
cat > "$AUTOSTART" <<EOF
[Desktop Entry]
Type=Application
Name=Conky (pride)
Comment=Painel de sistema detalhado
Exec=conky -p 10 -c $DEST/pride.conf
Icon=utilities-system-monitor
Terminal=false
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
X-KDE-autostart-after=panel
EOF

# ── subir agora ─────────────────────────────────────────────
say "subindo o painel"
if command -v systemd-run >/dev/null; then
    systemd-run --user --unit=conky-pride --collect /usr/bin/conky -c "$DEST/pride.conf" >/dev/null 2>&1 ||
        setsid conky -c "$DEST/pride.conf" >/dev/null 2>&1 < /dev/null &
else
    setsid conky -c "$DEST/pride.conf" >/dev/null 2>&1 < /dev/null &
fi

sleep 2
say "pronto. O painel fica atrás das janelas (camada 'below') — minimize para ver."
echo
echo "  reiniciar:  systemctl --user restart conky-pride"
echo "  parar:      systemctl --user stop conky-pride"
echo "  editar:     \$EDITOR $DEST/pride.conf"
