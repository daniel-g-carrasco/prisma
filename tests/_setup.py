# SPDX-License-Identifier: GPL-3.0-or-later
"""Set up the test profile before importing Qt."""

import importlib
import os
import sys
import tempfile
from pathlib import Path

import _userfolders

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = "prisma"
WINDOWS = os.name == "nt"
sys.path.insert(0, str(ROOT / "src"))


def shared(name):
    return importlib.import_module(PACKAGE + "." + name)


_userfolders.watch("prisma", "Prisma")
# Use the same spelling as subprocesses that resolve their checkout paths.
tempfile.tempdir = str(Path(tempfile.gettempdir()).resolve())
TEMP = _userfolders.isolate()
if TEMP is None:
    TEMP = Path(os.environ['XDG_CONFIG_HOME']).parent
for variable, folder in (("HOME", "profile"), ("USERPROFILE", "profile"),
                         ("APPDATA", "roaming"), ("LOCALAPPDATA", "local"),
                         ("TMP", "tmp"), ("TEMP", "tmp")):
    path = TEMP / folder
    path.mkdir(parents=True, exist_ok=True)
    os.environ[variable] = str(path)
os.environ["QT_QPA_PLATFORM"] = "offscreen"
os.environ["QML_DISABLE_DISK_CACHE"] = "1"
# Casa registers its shipped fonts from bytes. QPA's directory scanner on
# Windows cannot handle every Unicode path and would reload the same fonts.
font_folder = TEMP / 'qpa-fonts'
font_folder.mkdir(exist_ok=True)
os.environ['QT_QPA_FONTDIR'] = str(font_folder)
