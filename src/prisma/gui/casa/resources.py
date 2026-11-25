# SPDX-License-Identifier: GPL-3.0-or-later
"""Explicit kit resource layout; never search a user's home or another app."""
import gettext
from dataclasses import dataclass
from pathlib import Path

# The kit's icons (docs/30-icone.md): the name the window asks for and its Phosphor Duotone drawing, the file
# data/icons/phosphor/<drawing>-duotone.svg. Only these are in the kit; a Phosphor name in the right column is asked
# for as it is too. A new icon: one line here and its file, copied unchanged from @phosphor-icons/core 2.1.1.
ICONS = {
    'arrow-down': 'arrow-down', 'arrow-left': 'arrow-left', 'background': 'stack', 'book-open': 'book-open',
    'calculator': 'calculator', 'circle-question-mark': 'question', 'copy-plus': 'copy', 'download': 'download-simple',
    'ellipsis': 'dots-three', 'eraser': 'eraser', 'eye': 'eye', 'file-plus': 'file-plus', 'file-text': 'file-text',
    'folder-open': 'folder-open', 'grid-3x3': 'grid-nine', 'info': 'info', 'keyboard': 'keyboard', 'layers': 'stack',
    'layout-grid': 'squares-four', 'library': 'books', 'list-checks': 'list-checks', 'list-plus': 'list-plus',
    'lock': 'lock', 'lock-open': 'lock-open', 'log-out': 'sign-out', 'map': 'map-trifold',
    'measure': 'ruler', 'message-circle': 'chat-circle-dots', 'mouse-pointer-2': 'cursor', 'move': 'arrows-out-cardinal',
    'panel-bottom': 'square-half-bottom', 'panel-left': 'sidebar-simple', 'panel-right': 'sidebar-simple',
    'play': 'play', 'printer': 'printer', 'redo-2': 'arrow-u-up-right', 'ruler': 'ruler', 'save': 'floppy-disk',
    'search': 'magnifying-glass', 'select': 'cursor', 'settings': 'gear', 'shrink': 'arrows-in-simple',
    'sticky-note': 'note', 'table': 'table', 'trash': 'trash', 'undo-2': 'arrow-u-up-left', 'unlink': 'link-break',
    'upload': 'upload-simple', 'wand': 'magic-wand', 'x': 'x', 'zap': 'lightning',
    # the commands of Quotario's window (22/11/2026)
    'arrow-up': 'arrow-up', 'chart': 'chart-pie-slice', 'clipboard-copy': 'copy', 'columns-2': 'columns',
    'external-link': 'arrow-square-out', 'git-compare': 'git-diff', 'plus': 'plus', 'rotate-ccw': 'arrow-counter-clockwise',
    'rows-3': 'rows', 'sliders-horizontal': 'sliders-horizontal',
}
DRAWINGS = frozenset(ICONS.values())


@dataclass(frozen=True)
class Resources:
    root: Path

    def __post_init__(self):
        object.__setattr__(self, 'root', Path(self.root).resolve(strict=True))

    @property
    def fonts(self):
        return self.root / 'data/fonts'

    @property
    def icons(self):
        return self.root / 'data/icons'

    @property
    def locale(self):
        return self.root / 'locale'

    def icon(self, name):
        """The drawing of a name of ICONS; an unknown name is an error, not a blank."""
        drawing = ICONS.get(name, name if name in DRAWINGS else None)
        if drawing is None:
            raise FileNotFoundError(f'Icon {name!r} is not in the kit (resources.ICONS)')
        return self.icons / 'phosphor' / (drawing + '-duotone.svg')

    def translator(self, language):
        """An independent Casa gettext catalogue; English has no IT fallback."""
        if language == 'en':
            return gettext.NullTranslations().gettext
        return gettext.translation('casa', localedir=self.locale,
                                   languages=[language], fallback=False).gettext
