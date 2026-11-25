# SPDX-License-Identifier: GPL-3.0-or-later
"""One owner of heavy jobs and their delivery, independent of the toolkit."""

import logging
import math
import threading
import time
from itertools import count

from .workers.process import TERMINAL, Runner, error_event


class Handle:
    """The owner's view of one job, including a queued or restarted job."""

    def __init__(self, center, job_id, name, slot, function, arguments, build, topics, settle, on_event):
        self.id, self.name, self.slot = job_id, name, slot
        self.status, self.result, self.error = 'queued', None, ''
        self._center = center
        self._function, self._arguments, self._build = function, arguments, build
        self._topics, self._settle, self._on_event = topics, settle, on_event
        self._due = center.clock() + settle
        self._revision = 0
        self._token, self._run, self._progress = None, None, None

    @property
    def busy(self):
        return self.status in ('queued', 'running')

    @property
    def pid(self):
        process = self._run.process if self._run else None
        return process.pid if process else None

    def cancel(self):
        self._center.cancel(self)


class Center:
    """Call owner methods on one thread. Only pump() calls on_event.

    post() is an optional, thread-safe request to schedule pump() on the
    owner. It must return promptly and must not call back into the center.
    The owner also pumps on its timer while there are queued jobs. clock()
    supplies monotonic time for their quiet period.
    """

    def __init__(self, post=None, clock=time.monotonic):
        self.clock = clock
        self._post, self._posted = post, False
        self._closed = False
        self._ids = count(1)
        self._handles, self._slots = {}, {}
        self._lock = threading.Lock()
        self._mailbox, self._runs = {}, {}
        self._runner = Runner()

    def submit(self, function, arguments=(), *, name, slot=None, build=None, topics=(), settle=0.0, on_event=None):
        """Replace the slot's previous job and return a new Handle.

        The function is importable by module and name and accepts context=.
        arguments must be a stable, picklable snapshot. An optional cheap
        build() returns fresh arguments on the owner at each launch.
        A matching change restarts jobs with a builder after settle seconds,
        or discards jobs with a fixed snapshot.
        """
        if self._closed:
            raise RuntimeError('The work center is closed')
        if function.__qualname__ != function.__name__ or function.__name__ == '<lambda>':
            raise ValueError('A job needs an importable module-level function')
        if not math.isfinite(settle) or settle < 0:
            raise ValueError('Settle must be a finite, non-negative delay')
        slot = name if slot is None else slot
        handle = Handle(self, next(self._ids), name, slot, function, tuple(arguments),
                        build, tuple(topics), settle, on_event)
        previous = self._slots.get(slot)
        if previous is not None:
            self._finish(previous, 'cancelled')
        self._handles[handle.id] = self._slots[slot] = handle
        if not settle and build is None:
            self._launch(handle)
        return handle

    def changed(self, topics):
        """Invalidate matching snapshots, including results pending delivery."""
        topics = tuple(topics)
        for handle in tuple(self._handles.values()):
            if not any(topic == 'file' or topic == own or topic.startswith(own + ':')
                       for topic in topics for own in handle._topics):
                continue
            if handle._build is None:
                self._finish(handle, 'cancelled')
                continue
            self._invalidate(handle)
            handle.status = 'queued'
            handle._due = self.clock() + handle._settle
            handle._progress = None

    def cancel(self, handle):
        """Remove the row and suppress deliveries while its child stops."""
        if self._handles.get(handle.id) is handle:
            self._finish(handle, 'cancelled')

    def rows(self):
        """The active jobs, in submission order, ready for a toolkit adapter."""
        rows = []
        for handle in self._handles.values():
            progress = handle._progress or {}
            total = progress.get('total', 0)
            fraction = max(0.0, min(1.0, progress['current'] / total)) if total > 0 else None
            rows.append({
                'id': handle.id, 'slot': handle.slot, 'title': handle.name, 'state': handle.status,
                'phase': progress.get('message', ''), 'fraction': fraction, 'cancellable': True,
            })
        return rows

    def find(self, job_id):
        """Find the active handle for a row, if it is still present."""
        return self._handles.get(job_id)

    def pump(self, budget=0.003):
        """Start due jobs and deliver queued events within a turn's budget.

        A turn handles at least one ready item. Each callback must itself
        be short. True means there is more ready work for another turn.
        """
        if self._closed:
            return False
        deadline = time.perf_counter() + budget
        with self._lock:
            self._posted = False
        first = True
        for handle in tuple(self._handles.values()):
            if handle.status == 'queued' and handle._due <= self.clock():
                if not first and time.perf_counter() >= deadline:
                    return True
                self._launch(handle)
                first = False
                if self._closed:
                    return False
        while not self._closed and (first or time.perf_counter() < deadline):
            with self._lock:
                if not self._mailbox:
                    return False
                key = next(iter(self._mailbox))
                event = self._mailbox.pop(key)
                handle = self._runs[key[0]]
            self._deliver(handle, event)
            first = False
        with self._lock:
            return bool(self._mailbox)

    def close(self):
        """Drop pending deliveries and wait for every owned process to stop."""
        if self._closed:
            return
        with self._lock:
            self._closed = True
            self._mailbox.clear()
        for handle in tuple(self._handles.values()):
            self._finish(handle, 'cancelled')
        self._runner.close()

    def _launch(self, handle):
        revision = handle._revision
        try:
            arguments = tuple(handle._build()) if handle._build else handle._arguments
        except Exception as error:  # noqa: BLE001 (a builder failure is a job result)
            if handle.busy and handle._revision == revision:
                self._deliver(handle, error_event(error))
            return
        if not handle.busy or handle._revision != revision:
            return
        token = handle._token = object()
        with self._lock:
            self._runs[token] = handle
        handle.status = 'running'
        try:
            handle._run = self._runner.start(handle._function, arguments, handle.name,
                                             lambda event: self._incoming(token, event))
        except RuntimeError as error:
            self._incoming(token, error_event(error))

    def _incoming(self, token, event):
        kind = event['kind']
        key = (token, kind, event.get('key'))
        with self._lock:
            if self._closed or token not in self._runs:
                return
            self._mailbox[key] = event
            if self._post is not None and not self._posted:
                self._posted = True
                try:
                    self._post()
                except Exception:
                    self._posted = False
                    logging.getLogger(__name__).exception('Could not schedule job delivery')

    def _deliver(self, handle, event):
        kind = event['kind']
        callback = handle._on_event
        if kind == 'progress':
            handle._progress = event
        if kind in TERMINAL:
            handle.result = event.get('result')
            handle.error = event.get('message', '')
            self._finish(handle, kind)
        if callback is not None:
            try:
                callback(event)
            except Exception:
                logging.getLogger(__name__).exception('Job callback failed: %s', handle.name)

    def _invalidate(self, handle):
        token, run = handle._token, handle._run
        handle._revision += 1
        handle._token = None
        if token is not None:
            with self._lock:
                self._runs.pop(token)
                for key in tuple(self._mailbox):
                    if key[0] is token:
                        del self._mailbox[key]
        if run is not None:
            run.stop.set()

    def _finish(self, handle, status):
        self._invalidate(handle)
        handle.status = status
        del self._handles[handle.id]
        del self._slots[handle.slot]
        handle._arguments, handle._build, handle._on_event = (), None, None


class Job:
    """Compatibility facade for callers that poll one standalone job."""

    def __init__(self, function, arguments=(), *, name):
        self._center = Center()
        self._events = []
        self.status, self.result, self.error = 'running', None, ''
        self._closed = False
        self._handle = self._center.submit(function, arguments, name=name, on_event=self._events.append)

    @property
    def process(self):
        run = self._handle._run
        if run is None:
            return None
        run.started.wait()
        return run.process

    @property
    def pid(self):
        process = self.process
        return process.pid if process else None

    @property
    def busy(self):
        return not self._closed and self.status == 'running'

    def poll(self):
        if self._closed:
            return []
        self._center.pump()
        events = self._events[:]
        self._events.clear()
        run = self._handle._run
        # Polling clients close the job as soon as it stops being busy.
        cancelling = self._handle.status == 'cancelled' and run is not None and run.thread.is_alive()
        if self.busy and not self._handle.busy and not cancelling:
            self.status = self._handle.status
            self.result, self.error = self._handle.result, self._handle.error
            if self.status == 'cancelled' and not events:
                events.append({'kind': 'cancelled'})
        return events

    def cancel(self):
        self._handle.cancel()

    def close(self):
        if self._closed:
            return
        self._closed = True
        self._center.close()
        self._events.clear()
        if self.status == 'running':
            self.status = 'cancelled'

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()
