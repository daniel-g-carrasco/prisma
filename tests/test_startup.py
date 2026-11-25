# SPDX-License-Identifier: GPL-3.0-or-later
"""Start the actual Qt application from source with an isolated profile."""

import json
import os
import subprocess
import sys
import unittest

import _setup


class StartupTest(unittest.TestCase):
    def test_source_app_starts_in_english_and_can_use_italian(self):
        env = dict(os.environ, PYTHONPATH=str(_setup.ROOT / "src"), LANGUAGE="it")
        for options, language, title in (
            ([], "en", "IFC viewer in development"),
            (["--language", "it"], "it", "Visualizzatore IFC in sviluppo"),
        ):
            with self.subTest(language=language):
                run = subprocess.run(
                    [sys.executable, "-m", "prisma", "--smoke-test", *options],
                    cwd=_setup.ROOT,
                    env=env,
                    capture_output=True,
                    encoding="utf-8",
                    timeout=45,
                    check=False,
                )
                self.assertEqual(run.returncode, 0, run.stderr)
                self.assertEqual(
                    json.loads(run.stdout),
                    {"platform": "offscreen", "language": language, "title": title},
                )
