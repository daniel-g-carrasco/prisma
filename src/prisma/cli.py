# SPDX-License-Identifier: GPL-3.0-or-later
"""The source launcher and its isolated smoke mode."""

import argparse
import os
from contextlib import nullcontext
from pathlib import Path
from tempfile import TemporaryDirectory

from prisma import APP_NAME, __version__


def isolate(root: Path) -> None:
    for key in (
        "HOME", "USERPROFILE", "APPDATA", "LOCALAPPDATA", "TMP", "TEMP",
        "XDG_CONFIG_HOME", "XDG_STATE_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME", "XDG_RUNTIME_DIR",
    ):
        folder = root / key.lower()
        folder.mkdir(mode=0o700)
        os.environ[key] = str(folder)
    os.environ["QT_QPA_PLATFORM"] = "offscreen"
    os.environ["QT_QPA_PLATFORMTHEME"] = "offscreen"
    os.environ["QT_NO_XDG_DESKTOP_PORTAL"] = "1"
    os.environ["QML_DISABLE_DISK_CACHE"] = "1"
    os.environ["QT_QUICK_BACKEND"] = "software"
    font_folder = root / "qpa-fonts"
    font_folder.mkdir()
    os.environ["QT_QPA_FONTDIR"] = str(font_folder)


def main(argv=None):
    parser = argparse.ArgumentParser(prog="prisma", description="Prisma IFC viewer development shell.")
    parser.add_argument("--version", action="version", version=f"{APP_NAME} {__version__}")
    parser.add_argument("--language", choices=("en", "it"), default="en", help="interface language (default: en)")
    parser.add_argument("--smoke-test", action="store_true", help="start and close the window offscreen")
    args = parser.parse_args(argv)
    profile_context = TemporaryDirectory(prefix="prisma-smoke-") if args.smoke_test else nullcontext()
    with profile_context as profile:
        if profile is not None:
            isolate(Path(profile))
        from prisma.gui.application import run

        return run(args.language, smoke=args.smoke_test)
