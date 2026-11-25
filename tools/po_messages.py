# SPDX-License-Identifier: GPL-3.0-or-later
"""Explicit domains with separate source ownership; no discarded messages."""
REQUIRED_CATALOGS = ('po/it.po', 'po/casa/it.po')
DOMAINS = {'casa': {'sources': ['src/prisma/gui/casa'], 'po': 'po/casa',
                    'dest': 'src/prisma/gui/casa/locale', 'qml_calls': ['Theme.tr']}}
