# SPDX-License-Identifier: GPL-3.0-or-later
"""Document adapter. Hosts perform I/O and return a result or a Future.

Result: {'status': 'success'|'error'|'cancelled', 'message': str}.
Future completion is marshalled back onto this object's Qt thread. The host
must leave the document unchanged on error/cancel; snapshot/restore provides
an additional transaction boundary. Paths and recent entries come from hosts.
"""
from copy import deepcopy

from PySide6.QtCore import Property, QObject, Signal, Slot


class FilesController(QObject):
    changed = Signal()
    finished = Signal(str, str)
    fileDialogRequested = Signal(str, str, str, list)
    _completed = Signal(int, object)

    def __init__(self, service=None, *, recent=(), sections=(), recovery=None, parent=None):
        super().__init__(parent)
        # `recent`: the entries, or a function that gives them, asked again at every change (after an Open, for one)
        self.service, self._sections = service, list(sections)
        self._recent = recent if callable(recent) else list(recent)
        self.operation = ''     # the last operation asked: a failed Open is not a failed Save
        self._recovery, self._closed = recovery, False
        self._busy, self._message, self._serial = False, '', 0
        self._snapshot = None
        self._picker_pending = False
        self._completed.connect(self._finish)

    dirty = Property(bool, lambda self: bool(self.service and self.service.dirty), notify=changed)
    busy = Property(bool, lambda self: self._busy or self._picker_pending or bool(self.service and getattr(self.service, 'busy', False)), notify=changed)
    message = Property(str, lambda self: self._message, notify=changed)
    capabilities = Property('QVariantMap', lambda self: {
        key: bool(not self._closed and self.service and self.service.capabilities.get(key, False) and not self.busy)
        for key in ('new', 'open', 'save')}, notify=changed)
    # Why the service cannot do an operation (its `reasons`, the host's words): a viewer says why it does not save
    notes = Property('QVariantMap', lambda self: {
        key: str(reason) for key, reason in dict(getattr(self.service, 'reasons', None) or {}).items()
        if key in ('new', 'open', 'save') and reason and not self.service.capabilities.get(key, False)}, notify=changed)
    recent = Property('QVariantList', lambda self: deepcopy(list(self._recent() if callable(self._recent) else self._recent)), notify=changed)
    sections = Property('QVariantList', lambda self: deepcopy(self._sections), notify=changed)
    canRecover = Property(bool, lambda self: callable(self._recovery), constant=True)

    @Slot('QVariantList')
    def set_recent(self, entries):
        """The host's recent entries changed (a list, or the function that gives them)."""
        self._recent = entries if callable(entries) else list(entries)
        self.changed.emit()

    @Slot(str, str, str, 'QVariantList')
    def choose(self, operation, title, start, filters):
        if not self._closed and not self.busy:
            self._picker_pending = True
            self.changed.emit()
            self.fileDialogRequested.emit(operation, title, start, list(filters))

    @Slot()
    def cancelFileDialog(self):
        if self._picker_pending:
            self._picker_pending = False
            self.changed.emit()
            self.finished.emit('cancelled', '')

    @Slot(str, str, result=bool)
    def fileChosen(self, operation, path):
        if self._closed or not self._picker_pending:
            return False
        self._picker_pending = False
        self.changed.emit()
        return self.request('open' if operation == 'folder' else operation, path)

    @Slot(str, str, result=bool)
    def request(self, operation, path=''):
        if operation not in self.capabilities or not self.capabilities[operation]:
            return False
        if not path and operation in ('open', 'save') and hasattr(self.service, 'picker'):
            specification = self.service.picker(operation)
            if specification:
                self.choose(*specification)
                return True
        self._serial += 1
        serial = self._serial
        self.operation = operation
        self._snapshot = self.service.snapshot()
        self._busy, self._message = True, ''
        self.changed.emit()
        try:
            result = self.service.new() if operation == 'new' else getattr(self.service, operation)(path)
        except Exception as error:  # noqa: BLE001 (host result boundary; restores and reports the error)
            self._finish(serial, {'status': 'error', 'message': str(error)})
        else:
            if hasattr(result, 'add_done_callback'):
                def done(future):
                    if self._closed or serial != self._serial:
                        return
                    try:
                        value = future.result()
                    except Exception as error:  # noqa: BLE001 (host result boundary; restores and reports the error)
                        value = {'status': 'error', 'message': str(error)}
                    self._completed.emit(serial, value)
                result.add_done_callback(done)
            else:
                self._finish(serial, result)
        return True

    @Slot(int, object)
    def _finish(self, serial, result):
        if self._closed or serial != self._serial or not self._busy:
            return
        if not isinstance(result, dict) or result.get('status') not in ('success', 'error', 'cancelled'):
            result = {'status': 'error', 'message': 'Invalid document service result'}
        status = result['status']
        try:
            if status != 'success':
                self.service.restore(self._snapshot)
        finally:
            self._snapshot = None
            self._busy = False
            self._message = str(result.get('message', ''))
            self.changed.emit()
        self.finished.emit(status, self._message)

    @Slot(result=bool)
    def recover(self):
        if self._closed or not self.canRecover or self.busy:
            return False
        self._recovery()
        self.changed.emit()
        return True

    def close(self):
        self._closed = True
        self._serial += 1


class ReadOnlyDocuments(QObject):
    """The document service of a viewer: it opens and never saves, so it has nothing to lose at closing (`dirty` is
    always False and the window closes without asking). `open(path)` is the host's reader and returns a result or a
    Future, as FilesController expects. `save_reason` is the host's translated sentence that says why Save and Save as
    are off; `picker(operation)` optionally describes the selector of Open."""

    def __init__(self, open, *, save_reason='', picker=None, parent=None):
        super().__init__(parent)
        self._reader, self._picker, self._save_reason = open, picker, save_reason

    dirty = property(lambda self: False)
    busy = property(lambda self: False)
    capabilities = property(lambda self: {'new': False, 'open': True, 'save': False})
    reasons = property(lambda self: {'save': self._save_reason})

    def snapshot(self):
        return None

    def restore(self, snapshot):
        """Nothing to restore: a failed opening leaves the reader's previous document as it was."""

    def open(self, path=''):
        return self._reader(path)

    def save(self, path=''):
        return {'status': 'error', 'message': self._save_reason}

    def picker(self, operation):
        return self._picker(operation) if self._picker and operation == 'open' else None
