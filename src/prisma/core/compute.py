# SPDX-License-Identifier: GPL-3.0-or-later
"""Cooperative computation context, independent of UI and process ownership."""


class Cancelled(Exception):
    """The caller cancelled a computation at a safe checkpoint."""


class Context:
    def __init__(self, cancelled, send):
        self._cancelled, self._send = cancelled, send

    def check_cancelled(self):
        if self._cancelled.is_set():
            raise Cancelled()

    def progress(self, current, total=0, message=''):
        self.check_cancelled()
        self._send({'kind': 'progress', 'current': current, 'total': total, 'message': message})

    def partial(self, key, data):
        """Send a small intermediate result, replacing any undelivered value for the key."""
        self.check_cancelled()
        self._send({'kind': 'partial', 'key': key, 'data': data})
