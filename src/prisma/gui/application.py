# SPDX-License-Identifier: GPL-3.0-or-later
"""Load the Prisma development window with Casa."""

import json
import sys
from pathlib import Path

from PySide6.QtCore import QTimer, QtMsgType, QUrl, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication, QIcon
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuickControls2 import QQuickStyle

from prisma import APP_ID, APP_NAME, SLUG
from prisma.app.paths import shipped
from prisma.gui.casa.controls import install_controls
from prisma.gui.casa.resources import Resources
from prisma.gui.style.design_values import SCALES_JSON
from prisma.i18n import _, setup

GUI_ROOT = Path(__file__).resolve().parent
CHECKOUT = GUI_ROOT.parents[2]


def run(language: str, *, smoke: bool = False) -> int:
    setup(SLUG, CHECKOUT, language)
    QQuickStyle.setStyle("Basic")
    app = QGuiApplication([APP_NAME])
    app.setApplicationName(APP_NAME)
    app.setDesktopFileName(APP_ID)
    icon = shipped("icons", "hicolor", "scalable", "apps", APP_ID + ".svg", checkout=CHECKOUT, slug=SLUG)
    if icon:
        app.setWindowIcon(QIcon(str(icon)))

    resources = Resources(GUI_ROOT / "casa")
    warnings = []
    previous_handler = None
    if smoke:
        def capture(kind, _context, message):
            if kind in (QtMsgType.QtWarningMsg, QtMsgType.QtCriticalMsg, QtMsgType.QtFatalMsg):
                warnings.append(message)

        previous_handler = qInstallMessageHandler(capture)

    try:
        engine = QQmlApplicationEngine()
        install_controls(engine, resources=resources, translate=resources.translator(language), scales=json.loads(SCALES_JSON))
        engine.setInitialProperties({
            "title": APP_NAME,
            "statusTitle": _("IFC viewer in development"),
            "statusDescription": _("IFC files cannot be opened in this development build."),
        })
        engine.load(QUrl.fromLocalFile(str(GUI_ROOT / "qml" / "Window.qml")))
        roots = engine.rootObjects()
        if not roots:
            return 1
        if smoke:
            if not roots[0].isVisible():
                print("The development window did not open.", file=sys.stderr)
                return 1
            title = roots[0].property("statusTitle")
            QTimer.singleShot(0, app.quit)
        result = app.exec()
        if smoke and not warnings and not result:
            print(json.dumps({"platform": app.platformName(), "language": language, "title": title}))
        return int(bool(warnings or result)) if smoke else result
    finally:
        if smoke:
            qInstallMessageHandler(previous_handler)
            if warnings:
                print("\n".join(dict.fromkeys(warnings)), file=sys.stderr)
