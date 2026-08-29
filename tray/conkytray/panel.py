"""
Controle do painel Conky: estado, ligar/desligar, autostart e materialização
da config do usuário.

A config vive em ~/.config/conky/pride/ para o usuário poder editar. O pacote
guarda uma cópia intocada em /usr/share/conky-fedora-panel/ e só copia para o
usuário se ainda não existir — atualizar o pacote nunca sobrescreve o que ele
mexeu.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

UNIT = "conky-fedora-panel.service"
CONF_DIR = Path.home() / ".config/conky/pride"
CONF = CONF_DIR / "pride.conf"

# de onde vem a cópia pristina, na ordem em que procuramos
_TEMPLATE_DIRS = [
    Path("/usr/share/conky-fedora-panel"),
    Path("/usr/local/share/conky-fedora-panel"),
    Path(__file__).resolve().parent.parent.parent / "conky",  # rodando do repo
]

RAPL = Path("/sys/class/powercap/intel-rapl:0/energy_uj")
RAPL_RULE_NAME = "60-rapl.rules"
RAPL_RULE_DEST = "/etc/udev/rules.d/60-conky-rapl.rules"


@dataclass(frozen=True)
class State:
    running: bool = False
    enabled: bool = False
    stray: bool = False       # conky rodando com a nossa config, fora do systemd
    unit_known: bool = True   # a unit existe?

    @property
    def label(self) -> str:
        if self.stray:
            return "running (outside the service)"
        return "running" if self.running else "stopped"


def _run(args: list[str], timeout: float = 6.0) -> tuple[int, str]:
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return p.returncode, (p.stdout + p.stderr).strip()
    except (OSError, subprocess.SubprocessError) as exc:
        return 1, str(exc)


def template_dir() -> Path | None:
    for d in _TEMPLATE_DIRS:
        if (d / "pride.conf").is_file():
            return d
    return None


def ensure_config() -> bool:
    """Copia a config pristina para o usuário na primeira execução."""
    if CONF.is_file():
        return True
    src = template_dir()
    if src is None:
        return False
    (CONF_DIR / "scripts").mkdir(parents=True, exist_ok=True)
    shutil.copy2(src / "pride.conf", CONF)
    for sh in (src / "scripts").glob("*.sh"):
        dest = CONF_DIR / "scripts" / sh.name
        shutil.copy2(sh, dest)
        dest.chmod(0o755)
    return True


def reset_config() -> bool:
    """Volta para a versão do pacote, guardando a atual como .bak."""
    src = template_dir()
    if src is None:
        return False
    if CONF.is_file():
        shutil.copy2(CONF, CONF.with_suffix(".conf.bak"))
    CONF.unlink(missing_ok=True)
    for sh in (CONF_DIR / "scripts").glob("*.sh"):
        sh.unlink(missing_ok=True)
    return ensure_config()


def _stray_pids() -> list[int]:
    """conky rodando a nossa config sem ser pelo systemd (autostart antigo)."""
    out = []
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            cmd = (entry / "cmdline").read_bytes().replace(b"\0", b" ").decode()
        except OSError:
            continue
        if "conky" in cmd and str(CONF) in cmd:
            out.append(int(entry.name))
    return out


def state() -> State:
    rc_active, out_active = _run(["systemctl", "--user", "is-active", UNIT])
    running = out_active.strip() == "active"
    rc_en, out_en = _run(["systemctl", "--user", "is-enabled", UNIT])
    enabled = out_en.strip() == "enabled"
    unit_known = "not-found" not in out_en and "not-found" not in out_active
    stray = (not running) and bool(_stray_pids())
    return State(running=running or stray, enabled=enabled, stray=stray,
                 unit_known=unit_known)


def start() -> str:
    ensure_config()
    # se havia um conky solto com a nossa config, ele sai antes
    stop_stray()
    rc, out = _run(["systemctl", "--user", "start", UNIT], timeout=15)
    return "" if rc == 0 else out


def stop_stray() -> None:
    for pid in _stray_pids():
        try:
            os.kill(pid, 15)
        except OSError:
            pass


def stop() -> str:
    stop_stray()
    rc, out = _run(["systemctl", "--user", "stop", UNIT], timeout=15)
    return "" if rc == 0 else out


def restart() -> str:
    ensure_config()
    stop_stray()
    rc, out = _run(["systemctl", "--user", "restart", UNIT], timeout=15)
    return "" if rc == 0 else out


def set_enabled(on: bool) -> str:
    rc, out = _run(["systemctl", "--user", "enable" if on else "disable", UNIT],
                   timeout=15)
    # o autostart legado por .desktop atrapalharia; sai de cena
    legacy = Path.home() / ".config/autostart/conky-pride.desktop"
    if on:
        legacy.unlink(missing_ok=True)
    return "" if rc == 0 else out


# ── leitura de energia da CPU (RAPL) ────────────────────────
def rapl_readable() -> bool:
    return os.access(RAPL, os.R_OK)


def rapl_available() -> bool:
    return RAPL.exists()


def enable_rapl() -> str:
    """Instala a regra udev que libera os contadores de energia para o wheel."""
    src = template_dir()
    if src is None or not (src / RAPL_RULE_NAME).is_file():
        return "udev rule not found in the installed data files"
    script = (
        f'install -m 0644 "{src / RAPL_RULE_NAME}" "{RAPL_RULE_DEST}" && '
        'udevadm control --reload-rules && '
        'chgrp -R wheel /sys/devices/virtual/powercap/intel-rapl && '
        'chmod -R g+rX /sys/devices/virtual/powercap/intel-rapl'
    )
    rc, out = _run(["pkexec", "sh", "-c", script], timeout=90)
    return "" if rc == 0 else (out or "pkexec was cancelled")
