# SPDX-License-Identifier: GPL-3.0-or-later
"""Explicit window-scoped factories and exception-safe reverse teardown."""
from dataclasses import dataclass, field


@dataclass
class Part:
    id: str
    properties: dict = field(default_factory=dict)
    bind: object = None
    close: object = None
    _connections: list = field(default_factory=list, init=False)

    def connect(self, signal, callback):
        connection = signal.connect(callback)
        self._connections.append(connection)

    def disconnect(self):
        from PySide6.QtCore import QObject
        for connection in self._connections:
            QObject.disconnect(connection)
        self._connections.clear()


class Parts:
    def __init__(self, host, factories=()):
        self.installed, self.properties = {}, {}
        self._closed, self._bound = False, False
        try:
            for factory in factories:
                part = factory(host)
                if not isinstance(part, Part):
                    raise TypeError('Factory must return Part')
                if (not part.id or part.id in self.installed or
                        self.properties.keys() & part.properties.keys()):
                    try:
                        if part.close:
                            part.close()
                    finally:
                        part.disconnect()
                    raise ValueError('Duplicate part or property: ' + part.id)
                self.installed[part.id] = part
                self.properties.update(part.properties)
        except Exception as error:
            try:
                self.close()
            except Exception as closing:  # noqa: BLE001 (reports cleanup with the original failure)
                raise ExceptionGroup('Installation and cleanup failed', [error, closing]) from error
            raise

    def bind(self, window):
        if self._bound or self._closed:
            return
        self._bound = True
        try:
            for part in self.installed.values():
                if part.bind:
                    part.bind(window)
        except Exception as error:
            try:
                self.close()
            except Exception as closing:  # noqa: BLE001 (reports cleanup with the original failure)
                raise ExceptionGroup('Binding and cleanup failed', [error, closing]) from error
            raise

    def close(self):
        if self._closed:
            return
        self._closed = True
        errors = []
        for part in reversed(list(self.installed.values())):
            try:
                if part.close:
                    part.close()
            except Exception as error:  # noqa: BLE001 (aggregate; every part must close)
                errors.append(error)
            finally:
                part.disconnect()
        if errors:
            raise ExceptionGroup('Part cleanup failed', errors)
