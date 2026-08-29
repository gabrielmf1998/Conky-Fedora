"""Bandeja que liga, desliga e agenda o painel Conky."""

from __future__ import annotations

import subprocess

from PySide6.QtCore import QSettings, QTimer, QUrl
from PySide6.QtGui import QAction, QActionGroup, QDesktopServices
from PySide6.QtWidgets import QApplication, QMenu, QMessageBox, QSystemTrayIcon

from . import icons, panel

POLL_MS = 4000
TRAY_UNIT = "conky-panel-tray.service"
APP_NAME = "Conky Panel"


class Tray(QSystemTrayIcon):
    def __init__(self) -> None:
        super().__init__()
        self.settings = QSettings("conky-fedora-panel", "tray")
        self.state = panel.State()
        panel.ensure_config()

        self._build_menu()
        self.activated.connect(self._on_activated)

        self.timer = QTimer(self)
        self.timer.timeout.connect(self.refresh)
        self.timer.start(POLL_MS)

        self.refresh()
        self.show()

    # ── preferências ────────────────────────────────────────
    @property
    def style_name(self) -> str:
        s = self.settings.value("style", "waveform")
        return s if s in icons.STYLES else "waveform"

    @property
    def scheme(self) -> str:
        s = self.settings.value("scheme", "panel")
        return s if s in icons.SCHEMES else "panel"

    # ── menu ────────────────────────────────────────────────
    def _build_menu(self) -> None:
        self.menu = QMenu()

        self.header = QAction("...", self.menu)
        self.header.setEnabled(False)
        self.menu.addAction(self.header)
        self.subheader = QAction(str(panel.CONF_DIR), self.menu)
        self.subheader.setEnabled(False)
        self.menu.addAction(self.subheader)
        self.menu.addSeparator()

        self.act_panel = QAction("Panel", self.menu, checkable=True)
        self.act_panel.triggered.connect(self._toggle_panel)
        self.menu.addAction(self.act_panel)

        act_restart = QAction("Restart panel", self.menu)
        act_restart.triggered.connect(self._restart)
        self.menu.addAction(act_restart)

        boot = self.menu.addMenu("Start at login")
        self.act_boot_panel = QAction("Panel", boot, checkable=True)
        self.act_boot_panel.triggered.connect(
            lambda v: self._set_autostart(panel.UNIT, v))
        boot.addAction(self.act_boot_panel)
        self.act_boot_tray = QAction("Tray icon", boot, checkable=True)
        self.act_boot_tray.triggered.connect(
            lambda v: self._set_autostart(TRAY_UNIT, v))
        boot.addAction(self.act_boot_tray)

        self.menu.addSeparator()

        icon_menu = self.menu.addMenu("Icon")
        g_icon = QActionGroup(icon_menu)
        g_icon.setExclusive(True)
        for key, label in icons.STYLES.items():
            act = QAction(label, icon_menu, checkable=True)
            act.setChecked(key == self.style_name)
            act.triggered.connect(lambda _=False, k=key: self._set("style", k))
            g_icon.addAction(act)
            icon_menu.addAction(act)

        color_menu = self.menu.addMenu("Color")
        g_color = QActionGroup(color_menu)
        g_color.setExclusive(True)
        for key, (label, _hex) in icons.SCHEMES.items():
            act = QAction(label, color_menu, checkable=True)
            act.setChecked(key == self.scheme)
            act.triggered.connect(lambda _=False, k=key: self._set("scheme", k))
            g_color.addAction(act)
            color_menu.addAction(act)

        self.menu.addSeparator()

        act_edit = QAction("Edit config…", self.menu)
        act_edit.triggered.connect(
            lambda: QDesktopServices.openUrl(QUrl.fromLocalFile(str(panel.CONF))))
        self.menu.addAction(act_edit)

        act_open = QAction("Open config folder", self.menu)
        act_open.triggered.connect(
            lambda: QDesktopServices.openUrl(
                QUrl.fromLocalFile(str(panel.CONF_DIR))))
        self.menu.addAction(act_open)

        act_reset = QAction("Reset config to shipped version…", self.menu)
        act_reset.triggered.connect(self._reset)
        self.menu.addAction(act_reset)

        self.act_rapl = QAction("Enable CPU power readings…", self.menu)
        self.act_rapl.triggered.connect(self._enable_rapl)
        self.menu.addAction(self.act_rapl)

        self.menu.addSeparator()
        act_quit = QAction("Quit tray", self.menu)
        act_quit.triggered.connect(QApplication.quit)
        self.menu.addAction(act_quit)

        self.setContextMenu(self.menu)

    def _set(self, key: str, value) -> None:
        self.settings.setValue(key, value)
        self.refresh()

    def _on_activated(self, reason) -> None:
        if reason in (QSystemTrayIcon.Trigger, QSystemTrayIcon.MiddleClick):
            self.refresh()
            geo = self.geometry()
            if geo.isValid():
                self.menu.popup(geo.bottomLeft())

    # ── ações ───────────────────────────────────────────────
    def _toggle_panel(self, want_on: bool) -> None:
        err = panel.start() if want_on else panel.stop()
        if err:
            self._msg(APP_NAME, err.splitlines()[0][:180])
        self.refresh()

    def _restart(self) -> None:
        err = panel.restart()
        self._msg(APP_NAME, err.splitlines()[0][:180] if err else "Panel restarted.")
        self.refresh()

    @staticmethod
    def _is_enabled(unit: str) -> bool:
        try:
            out = subprocess.run(["systemctl", "--user", "is-enabled", unit],
                                 capture_output=True, text=True, timeout=5)
            return out.stdout.strip() == "enabled"
        except (OSError, subprocess.SubprocessError):
            return False

    def _set_autostart(self, unit: str, on: bool) -> None:
        if unit == panel.UNIT:
            err = panel.set_enabled(on)
        else:
            verb = "enable" if on else "disable"
            try:
                subprocess.run(["systemctl", "--user", verb, unit],
                               capture_output=True, timeout=10)
                err = ""
            except (OSError, subprocess.SubprocessError) as exc:
                err = str(exc)
        if err:
            self._msg(APP_NAME, err.splitlines()[0][:180])
        self.refresh()

    def _reset(self) -> None:
        box = QMessageBox()
        box.setWindowTitle("Reset config")
        box.setIcon(QMessageBox.Warning)
        box.setText("Replace your panel config with the version shipped in the "
                    "package?")
        box.setInformativeText(
            f"Your current {panel.CONF.name} is copied to {panel.CONF.name}.bak "
            "first, and the helper scripts are replaced too.")
        box.setStandardButtons(QMessageBox.Reset | QMessageBox.Cancel)
        box.setDefaultButton(QMessageBox.Cancel)
        if box.exec() != QMessageBox.Reset:
            return
        if panel.reset_config():
            panel.restart()
            self._msg(APP_NAME, "Config reset to the shipped version.")
        else:
            self._msg(APP_NAME, "Could not find the shipped config to restore.")
        self.refresh()

    def _enable_rapl(self) -> None:
        box = QMessageBox()
        box.setWindowTitle("Enable CPU power readings")
        box.setIcon(QMessageBox.Information)
        box.setText("Install a udev rule so the panel can read CPU power draw?")
        box.setInformativeText(
            "The kernel keeps the RAPL energy counters root-only because "
            "high-resolution energy readings can be used as a side channel "
            "(PLATYPUS, CVE-2020-8694).\n\n"
            "This grants read access to the 'wheel' group only — not to "
            "everyone. Without it, the panel's Power field stays empty.\n\n"
            "You will be asked for your password.")
        box.setStandardButtons(QMessageBox.Ok | QMessageBox.Cancel)
        if box.exec() != QMessageBox.Ok:
            return
        err = panel.enable_rapl()
        self._msg(APP_NAME, err.splitlines()[0][:180] if err
                  else "CPU power readings enabled.")
        self.refresh()

    def _msg(self, title: str, body: str) -> None:
        self.showMessage(title, body,
                         icons.make_icon(self.style_name, self.state.running,
                                         self.scheme), 5000)

    # ── ciclo ───────────────────────────────────────────────
    def refresh(self) -> None:
        self.state = panel.state()
        st = self.state

        self.setIcon(icons.make_icon(self.style_name, st.running, self.scheme))
        self.header.setText(f"Conky panel — {st.label}")

        self.act_panel.blockSignals(True)
        self.act_panel.setChecked(st.running)
        self.act_panel.blockSignals(False)

        self.act_boot_panel.blockSignals(True)
        self.act_boot_panel.setChecked(self._is_enabled(panel.UNIT))
        self.act_boot_panel.blockSignals(False)
        self.act_boot_tray.blockSignals(True)
        self.act_boot_tray.setChecked(self._is_enabled(TRAY_UNIT))
        self.act_boot_tray.blockSignals(False)

        self.act_rapl.setVisible(panel.rapl_available()
                                 and not panel.rapl_readable())

        tip = [f"Conky panel: {st.label}"]
        if st.stray:
            tip.append("started outside the service — toggling will take it over")
        if not st.unit_known:
            tip.append("service unit not installed")
        self.setToolTip("\n".join(tip))


def main() -> int:
    app = QApplication([])
    app.setApplicationName(APP_NAME)
    app.setDesktopFileName("conky-panel-tray")
    app.setQuitOnLastWindowClosed(False)

    if not QSystemTrayIcon.isSystemTrayAvailable():
        print("system tray unavailable", flush=True)
        return 1

    tray = Tray()  # noqa: F841 — precisa continuar referenciado
    return app.exec()
