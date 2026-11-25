# SPDX-License-Identifier: GPL-3.0-or-later
"""Select Qt's installed portal theme for source launches on Linux."""
import os
import sys
from pathlib import Path

from PySide6.QtCore import QLibraryInfo


def configure_portal(*, environ=None, platform=None, plugins=None):
    env = os.environ if environ is None else environ
    if (platform or sys.platform) != 'linux' or 'QT_QPA_PLATFORMTHEME' in env:
        return False
    if env.get('FLATPAK_ID') or Path('/.flatpak-info').exists():
        return False
    root = Path(plugins or QLibraryInfo.path(QLibraryInfo.LibraryPath.PluginsPath))
    if (root / 'platformthemes/libqxdgdesktopportal.so').is_file():
        env['QT_QPA_PLATFORMTHEME'] = 'xdgdesktopportal'
        return True
    return False
