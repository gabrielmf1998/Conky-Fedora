"""
Ícones da bandeja, desenhados em runtime com QPainter.

Vetor num espaço 100x100, escalado para o tamanho pedido: nítido em 22px na
bandeja e em 128px na notificação, sem nenhum arquivo de imagem.

Cada estilo tem duas leituras claras: painel ligado (traço cheio, na cor
escolhida) e desligado (contorno apagado, e nos estilos de onda a linha fica
reta — a métrica parou).
"""

from __future__ import annotations

import math

from PySide6.QtCore import QPointF, QRectF, Qt
from PySide6.QtGui import QColor, QIcon, QPainter, QPainterPath, QPen, QPixmap

SIZES = (22, 32, 48, 64, 128)

STYLES = {
    "waveform": "Waveform",
    "panel":    "Panel card",
    "gauge":    "Gauge",
    "bars":     "Bars",
    "chip":     "CPU chip",
    "pulse":    "Pulse line",
    "dot":      "Status dot",
}

SCHEMES = {
    "panel":   ("Panel violet", "#a45cff"),
    "white":   ("White", "#ffffff"),
    "mono":    ("Soft grey", "#c9c9d2"),
    "cyan":    ("Cyan", "#22d3ee"),
    "green":   ("Green", "#3ddc84"),
    "amber":   ("Amber", "#ffb020"),
    "magenta": ("Magenta", "#ff5ecb"),
    "blue":    ("Blue", "#4d8dff"),
    "red":     ("Red", "#ff453a"),
}

OFF = QColor(255, 255, 255, 70)


def scheme_color(scheme: str) -> QColor:
    return QColor(SCHEMES.get(scheme, SCHEMES["panel"])[1])


def _wave_path(flat: bool, amp: float = 1.0) -> QPainterPath:
    """Curva do gráfico; achatada quando o painel está parado."""
    pts = [(14, 62), (24, 52), (32, 66), (41, 40), (50, 58),
           (58, 46), (67, 64), (76, 50), (86, 58)]
    path = QPainterPath()
    for i, (x, y) in enumerate(pts):
        yy = 58 if flat else 58 + (y - 58) * amp
        if i == 0:
            path.moveTo(QPointF(x, yy))
        else:
            path.lineTo(QPointF(x, yy))
    return path


def _paint_waveform(p: QPainter, c: QColor, on: bool) -> None:
    frame = QRectF(9, 20, 82, 60)
    p.setBrush(Qt.NoBrush)
    p.setPen(QPen(OFF if not on else c, 7, Qt.SolidLine, Qt.SquareCap, Qt.RoundJoin))
    p.drawRoundedRect(frame, 12, 12)
    p.setPen(QPen(c if on else OFF, 7, Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin))
    p.drawPath(_wave_path(flat=not on))


def _paint_panel(p: QPainter, c: QColor, on: bool) -> None:
    card = QRectF(16, 10, 68, 80)
    p.setBrush(Qt.NoBrush)
    p.setPen(QPen(c if on else OFF, 7, Qt.SolidLine, Qt.SquareCap, Qt.RoundJoin))
    p.drawRoundedRect(card, 11, 11)
    p.setPen(Qt.NoPen)
    p.setBrush(c if on else OFF)
    p.drawRoundedRect(QRectF(25, 22, 34, 8), 4, 4)          # título
    widths = (50, 38, 44) if on else (26, 26, 26)
    for i, w in enumerate(widths):
        p.drawRoundedRect(QRectF(25, 42 + i * 14, w, 6), 3, 3)


def _paint_gauge(p: QPainter, c: QColor, on: bool) -> None:
    rect = QRectF(13, 16, 74, 74)
    start, span = 210 * 16, -240 * 16
    p.setBrush(Qt.NoBrush)
    p.setPen(QPen(OFF, 10, Qt.SolidLine, Qt.RoundCap))
    p.drawArc(rect, start, span)
    if on:
        p.setPen(QPen(c, 10, Qt.SolidLine, Qt.RoundCap))
        p.drawArc(rect, start, int(span * 0.68))
    ang = math.radians(210 - (240 * (0.68 if on else 0.0)))
    cx, cy, r = 50, 53, 26
    p.setPen(QPen(c if on else OFF, 7, Qt.SolidLine, Qt.RoundCap))
    p.drawLine(QPointF(cx, cy),
               QPointF(cx + r * math.cos(ang), cy - r * math.sin(ang)))


def _paint_bars(p: QPainter, c: QColor, on: bool) -> None:
    heights = (34, 56, 26, 48) if on else (16, 16, 16, 16)
    p.setPen(Qt.NoPen)
    for i, h in enumerate(heights):
        p.setBrush(c if on else OFF)
        p.drawRoundedRect(QRectF(14 + i * 20, 84 - h, 14, h), 4, 4)


def _paint_chip(p: QPainter, c: QColor, on: bool) -> None:
    body = QRectF(24, 24, 52, 52)
    p.setBrush(Qt.NoBrush)
    p.setPen(QPen(c if on else OFF, 7, Qt.SolidLine, Qt.SquareCap, Qt.MiterJoin))
    p.drawRoundedRect(body, 8, 8)
    p.setPen(QPen(c if on else OFF, 6, Qt.SolidLine, Qt.RoundCap))
    for i in range(3):
        o = 34 + i * 16
        p.drawLine(QPointF(o, 12), QPointF(o, 24))
        p.drawLine(QPointF(o, 76), QPointF(o, 88))
        p.drawLine(QPointF(12, o), QPointF(24, o))
        p.drawLine(QPointF(76, o), QPointF(88, o))
    if on:
        p.setPen(Qt.NoPen)
        p.setBrush(c)
        p.drawRoundedRect(QRectF(38, 38, 24, 24), 4, 4)


def _paint_pulse(p: QPainter, c: QColor, on: bool) -> None:
    p.setBrush(Qt.NoBrush)
    p.setPen(QPen(c if on else OFF, 9, Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin))
    if on:
        path = QPainterPath(QPointF(8, 56))
        for pt in [(28, 56), (36, 26), (46, 78), (56, 44), (64, 56), (92, 56)]:
            path.lineTo(QPointF(*pt))
        p.drawPath(path)
    else:
        p.drawLine(QPointF(8, 56), QPointF(92, 56))


def _paint_dot(p: QPainter, c: QColor, on: bool) -> None:
    p.setBrush(Qt.NoBrush)
    p.setPen(QPen(c if on else OFF, 8))
    p.drawEllipse(QRectF(18, 18, 64, 64))
    if on:
        p.setPen(Qt.NoPen)
        p.setBrush(c)
        p.drawEllipse(QPointF(50, 50), 16, 16)


_PAINTERS = {
    "waveform": _paint_waveform,
    "panel": _paint_panel,
    "gauge": _paint_gauge,
    "bars": _paint_bars,
    "chip": _paint_chip,
    "pulse": _paint_pulse,
    "dot": _paint_dot,
}


def _render(size: int, style: str, on: bool, scheme: str) -> QPixmap:
    pm = QPixmap(size, size)
    pm.fill(Qt.transparent)
    p = QPainter(pm)
    p.setRenderHint(QPainter.Antialiasing, True)
    p.scale(size / 100.0, size / 100.0)
    _PAINTERS.get(style, _paint_waveform)(p, scheme_color(scheme), on)
    p.end()
    return pm


def make_icon(style: str, on: bool, scheme: str = "panel") -> QIcon:
    icon = QIcon()
    for s in SIZES:
        icon.addPixmap(_render(s, style, on, scheme))
    return icon
