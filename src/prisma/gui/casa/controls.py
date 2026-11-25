# SPDX-License-Identifier: GPL-3.0-or-later
"""Shared icon source and installation of the Quick control library."""
from __future__ import annotations

import os
import sys
from collections.abc import Callable
from urllib.parse import unquote

from PySide6.QtCore import QByteArray, QPointF, QRect, QRectF, QSize, Qt
from PySide6.QtGui import QColor, QImage, QPainter, QPainterPath, QPen
from PySide6.QtQuick import QQuickImageProvider
from PySide6.QtSvg import QSvgRenderer

from .resources import Resources
from .style import symbols
from .style.icons import svg
from .tokens import ThemeTokens, install_theme

_raster_registered = False


class IconProvider(QQuickImageProvider):
    """Render the Widgets' authoritative SVGs at the requested physical size."""

    def __init__(self, theme=None, resources=None):
        super().__init__(QQuickImageProvider.ImageType.Image)
        self._theme = theme
        self._resources = resources
        self._progress_style = None
        self._rendered = {}

    def requestImage(self, identifier, size, requestedSize):
        # The same icon at the same size is asked again whenever its item is made or laid out again (45 renders at
        # each resize, 06/11/2026): rendered once, kept (a few hundred small images at most).
        key = (identifier, requestedSize.width(), requestedSize.height())
        found = self._rendered.get(key)
        if found is None:
            if len(self._rendered) > 2048:
                self._rendered.clear()
            image = self._render(identifier, size, requestedSize)
            found = self._rendered[key] = (image, QSize(size))
        else:
            size.setWidth(found[1].width())
            size.setHeight(found[1].height())
        return found[0]

    def _render(self, identifier, size, requestedSize):
        parts = identifier.split('/')
        name = parts[0]
        color = QColor(unquote(parts[1])) if len(parts) > 1 else QColor('black')
        dimensions = requestedSize if requestedSize.isValid() else QSize(24, 24)
        dimensions = QSize(max(1, dimensions.width()), max(1, dimensions.height()))
        if name.startswith('progress:'):
            ratio = float(parts[2])
            dimensions = QSize(round(32 * ratio), round(6 * ratio))
        image = QImage(dimensions, QImage.Format.Format_ARGB32_Premultiplied)
        image.fill(Qt.GlobalColor.transparent)
        if name.startswith('progress:'):
            # Fusion is the Widgets' base style. Cache only its two static skins;
            # Quick stretches their middle and animates geometry without Python.
            from PySide6.QtGui import QPalette
            from PySide6.QtWidgets import QStyle, QStyleFactory, QStyleOptionProgressBar

            from .style import theme_colors
            from .style.theme import qpalette
            if self._progress_style is None:
                self._progress_style = QStyleFactory.create('Fusion')
            image.setDevicePixelRatio(dimensions.height() / 6)
            option = QStyleOptionProgressBar()
            option.rect = QRect(0, 0, 32, 6)
            option.minimum, option.maximum, option.progress = 0, 100, 100
            option.textVisible = False
            option.state = QStyle.StateFlag.State_Horizontal
            enabled = parts[-1] != 'off'
            if enabled:
                option.state |= QStyle.StateFlag.State_Enabled
            option.palette = qpalette(theme_colors.palette(self._theme.colors, self._theme.dark))
            option.palette.setCurrentColorGroup(QPalette.ColorGroup.Active if enabled else QPalette.ColorGroup.Disabled)
            painter = QPainter(image)
            element = (QStyle.ControlElement.CE_ProgressBarGroove if name.startswith('progress:groove')
                       else QStyle.ControlElement.CE_ProgressBarContents)
            self._progress_style.drawControl(element, option, painter)
            painter.end()
            # BorderImage treats provider pixels as logical pixels. Split the
            # caps explicitly so high-DPI skins keep their six logical rows.
            cap = round(3 * ratio)
            if name.endswith('-left'):
                image = image.copy(0, 0, cap, dimensions.height())
            elif name.endswith('-right'):
                image = image.copy(dimensions.width() - cap, 0, cap, dimensions.height())
            elif name.endswith('-middle'):
                image = image.copy(cap, 0, dimensions.width() - 2 * cap, dimensions.height())
            dimensions = image.size()
            size.setWidth(dimensions.width())
            size.setHeight(dimensions.height())
            return image
        painter = QPainter(image)
        rect = QRectF(0, 0, dimensions.width(), dimensions.height())
        if name.startswith('sign:'):
            painter.setRenderHint(QPainter.RenderHint.Antialiasing)
            painter.fillPath(symbols.sign(name.removeprefix('sign:'), rect), color)
        elif name == 'control:grip':
            # Tiny antialiased circles have no opaque pixel at 100%. Snap each
            # dot's box too, with square two-pixel dots and rounded larger ones.
            dot = max(2, round(dimensions.width() / 10))
            painter.setRenderHint(QPainter.RenderHint.Antialiasing, dot > 2)
            painter.setPen(Qt.PenStyle.NoPen)
            painter.setBrush(color)
            for x in (7, 13):
                for y in (5, 10, 15):
                    left = round(x * dimensions.width() / 20 - dot / 2)
                    top = round(y * dimensions.height() / 20 - dot / 2)
                    radius = 1 if dot > 2 else 0
                    painter.drawRoundedRect(QRectF(left, top, dot, dot), radius, radius)
        elif name == 'control:close':
            painter.setRenderHint(QPainter.RenderHint.Antialiasing)
            painter.scale(dimensions.width() / 20, dimensions.height() / 20)
            painter.setPen(QPen(color, 1.5))
            painter.drawLine(QPointF(6.5, 6.5), QPointF(13.5, 13.5))
            painter.drawLine(QPointF(6.5, 13.5), QPointF(13.5, 6.5))
        elif name in ('control:star', 'control:star-full'):
            # R518: the favourite's star, drawn: «★» and «☆» are not in the program's font and came out as an empty box
            # wherever Qt finds no other font with them (offscreen, a Linux without symbol fonts)
            import math
            painter.setRenderHint(QPainter.RenderHint.Antialiasing)
            painter.scale(dimensions.width() / 20, dimensions.height() / 20)
            star = QPainterPath()
            for k in range(10):
                r = 7 if k % 2 == 0 else 3
                a = -math.pi / 2 + k * math.pi / 5
                p = QPointF(10 + r * math.cos(a), 10.6 + r * math.sin(a))
                star.moveTo(p) if k == 0 else star.lineTo(p)
            star.closeSubpath()
            pen = QPen(color, 1.3)
            pen.setJoinStyle(Qt.PenJoinStyle.RoundJoin)
            painter.setPen(pen)
            if name == 'control:star-full':
                painter.setBrush(color)
            painter.drawPath(star)
        elif name.startswith('control:arrow-'):
            # R592: the full arrow of M.Arrow, rows of whole pixels of the size asked (the item's size times the
            # screen's ratio), each two shorter than the one before, no antialiasing: nothing half covered to blur
            across = name.endswith(('-right', '-left'))
            depth = dimensions.width() if across else dimensions.height()
            depth = min(depth, ((dimensions.height() if across else dimensions.width()) + 1) // 2)
            for step in range(depth):
                span = 2 * (depth - step) - 1
                line = depth - 1 - step if name.endswith(('-up', '-left')) else step
                if across:
                    painter.fillRect(line, (dimensions.height() - span) // 2, 1, span, color)
                else:
                    painter.fillRect((dimensions.width() - span) // 2, line, span, 1, color)
        elif name == 'control:chevron-down':
            painter.setRenderHint(QPainter.RenderHint.Antialiasing)
            painter.scale(dimensions.width() / 20, dimensions.height() / 20)
            pen = QPen(color, 1.5)
            pen.setCapStyle(Qt.PenCapStyle.RoundCap)
            pen.setJoinStyle(Qt.PenJoinStyle.RoundJoin)
            painter.setPen(pen)
            painter.drawPolyline([QPointF(6, 8.5), QPointF(10, 12.5), QPointF(14, 8.5)])
        elif name in ('control:chevron-right', 'control:minus', 'control:plus', 'control:more'):
            # R21-F3: the signs that were characters in a text («›», «−», «+», «⋮»), on the grid of chevron-down (20
            # units, line 1.5, round ends): no symbol font needed, the same drawing at every scale and on every system
            painter.setRenderHint(QPainter.RenderHint.Antialiasing)
            painter.scale(dimensions.width() / 20, dimensions.height() / 20)
            if name == 'control:more':
                painter.setPen(Qt.PenStyle.NoPen)
                painter.setBrush(color)
                for y in (5, 10, 15):
                    painter.drawEllipse(QPointF(10, y), 1.4, 1.4)
            else:
                pen = QPen(color, 1.5)
                pen.setCapStyle(Qt.PenCapStyle.RoundCap)
                pen.setJoinStyle(Qt.PenJoinStyle.RoundJoin)
                painter.setPen(pen)
                if name == 'control:chevron-right':
                    painter.drawPolyline([QPointF(8.5, 6), QPointF(12.5, 10), QPointF(8.5, 14)])
                else:
                    painter.drawLine(QPointF(5.5, 10), QPointF(14.5, 10))
                    if name == 'control:plus':
                        painter.drawLine(QPointF(10, 5.5), QPointF(10, 14.5))
        elif name.startswith('field:'):
            from .style.theme import ARROWS
            path, w, h = ARROWS[name.removeprefix('field:')]
            data = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}">'
                    f'<path d="{path}" fill="none" stroke="{color.name()}" stroke-width="2" '
                    'stroke-linecap="round" stroke-linejoin="round"/></svg>')
            renderer = QSvgRenderer(QByteArray(data.encode()))
            renderer.render(painter, rect)
        elif name.startswith('mark:'):
            # a mark on the views (the plan, the 3D view): the symbol with its white sign in a thin white edge
            # (symbols.paint_view, Daniel 14/11/2026), no disc round it
            symbol = name.removeprefix('mark:')
            symbol = symbols.LEVEL.get(symbol, symbol)
            if symbol in symbols.NAMES:
                symbols.paint_view(painter, rect, symbol)
        elif name.startswith('symbol:'):
            symbol = name.removeprefix('symbol:')
            symbol = symbols.LEVEL.get(symbol, symbol)
            if symbol in symbols.NAMES:
                symbols.paint(painter, rect, symbol, dark=len(parts) > 2 and parts[2] == 'dark',
                              off=len(parts) > 3 and parts[3] == 'off', round_=len(parts) > 4 and parts[4] == 'round')
        else:
            duo = QColor(unquote(parts[5])) if len(parts) > 5 else QColor(color)
            if len(parts) <= 5:
                duo.setAlphaF(0.2)
            weight = parts[6] if len(parts) > 6 else 'regular'
            renderer = QSvgRenderer(QByteArray(svg(name, self._resources, color, duo, weight)))
            if renderer.isValid():
                painter.setOpacity(color.alphaF())
                renderer.render(painter, rect)
        painter.end()
        size.setWidth(dimensions.width())
        size.setHeight(dimensions.height())
        return image


def install_controls(engine, options=None, *, resources: Resources,
                     translate: Callable[[str], str], scales=None) -> ThemeTokens:
    """Idempotently install Theme and icons; return this engine's ThemeTokens."""
    global _raster_registered
    if not _raster_registered:
        # On high-DPI Windows, Qt sizes the image atlas from the native window.
        # Casa's small icons fit a smaller atlas. Larger images still get
        # individual textures. Leave explicit host graphics settings intact.
        atlas = ('QSG_ATLAS_WIDTH', 'QSG_ATLAS_HEIGHT')
        if (sys.platform == 'win32' and os.environ.get('QSG_RHI_BACKEND', 'd3d11').lower() == 'd3d11'
                and os.environ.get('QT_QUICK_BACKEND') != 'software'
                and not any(key in os.environ for key in atlas)):
            os.environ.update(dict.fromkeys(atlas, '1024'))
        from PySide6.QtQml import qmlRegisterType

        from .columns import TableProjection
        from .row_extension import RowExtension
        from .surface import RasterSurface
        from .table_accessibility import install as install_table_accessibility
        install_table_accessibility()
        from .table_text import CellTextGuard, TableText
        qmlRegisterType(RasterSurface, 'Casa.Raster', 1, 0, 'RasterSurface')
        qmlRegisterType(TableProjection, 'Casa.Tables', 1, 0, 'TableProjection')
        qmlRegisterType(RowExtension, 'Casa.Tables', 1, 0, 'RowExtension')
        qmlRegisterType(TableText, 'Casa.Tables', 1, 0, 'TableText')
        qmlRegisterType(CellTextGuard, 'Casa.Tables', 1, 0, 'CellTextGuard')
        _raster_registered = True
    tokens = install_theme(engine, options, resources=resources, translate=translate, scales=scales)
    if not getattr(engine, '_casa_icons', None):
        provider = IconProvider(tokens, resources)
        engine.addImageProvider('casa', provider)
        engine._casa_icons = provider
        engine._casa_resources = provider._resources
    from . import text_editing
    text_editing.install(engine, translate=translate)
    return tokens
