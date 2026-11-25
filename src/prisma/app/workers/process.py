# SPDX-License-Identifier: GPL-3.0-or-later
"""Spawn and reap workers off the owner's thread, including pipe decoding."""

import importlib
import importlib.util
import multiprocessing
import runpy
import sys
import threading
from pathlib import Path

TERMINAL = frozenset(('completed', 'cancelled', 'error'))
GRACE = .25
JOIN_TIMEOUT = 1.0


def error_event(error):
    return {'kind': 'error', 'message': f'{type(error).__name__}: {error}'}


def _execute(module, function, arguments, cancelled, output):
    from ...core.compute import Cancelled, Context

    try:
        context = Context(cancelled, output.send)
        context.check_cancelled()
        compute = getattr(importlib.import_module(module), function)
        result = compute(*arguments, context=context)
        context.check_cancelled()
        output.send({'kind': 'completed', 'result': result})
    except Cancelled:
        output.send({'kind': 'cancelled'})
    except Exception as error:  # noqa: BLE001 (report worker failures across the process boundary)
        output.send(error_event(error))


def _bootstrap(package, root, request, output):
    with output:
        if package not in sys.modules:
            root = Path(root)
            spec = importlib.util.spec_from_file_location(
                package, root / '__init__.py', submodule_search_locations=[str(root)])
            module = importlib.util.module_from_spec(spec)
            sys.modules[package] = module
            spec.loader.exec_module(module)
        worker = importlib.import_module(package + '.app.workers.process')
        worker._execute(*request, output)


class Run:
    def __init__(self, runner, function, arguments, name, deliver):
        self.process = None
        self.started = threading.Event()
        self.stop = threading.Event()
        self.shutdown_error = None
        self._terminal = None
        self._deliver = deliver
        self.thread = threading.Thread(
            target=self._supervise, args=(runner, function, arguments, name),
            name=f'{name}-supervisor', daemon=True)

    def _supervise(self, runner, function, arguments, name):
        try:
            if not self.stop.is_set():
                self._spawn(function, arguments, name)
        except Exception as error:  # noqa: BLE001 (startup and transport errors are job results)
            if not self.stop.is_set():
                self._deliver(error_event(error))
        finally:
            self.started.set()
            runner.finished(self)

    def _spawn(self, function, arguments, name):
        context = multiprocessing.get_context('spawn')
        cancelled = context.Event()
        package = __package__.split('.')[0]
        root = str(Path(__file__).resolve().parents[2])
        incoming, output = context.Pipe(duplex=False)
        with incoming, output:
            request = (function.__module__, function.__name__, arguments, cancelled)
            bootstrap = (package, root, request, output)
            if getattr(sys, 'frozen', False):
                target, args = _bootstrap, bootstrap
            else:
                # A host can load the package from a directory without
                # installing it or adding its parent to sys.path.
                target = runpy.run_path
                args = (__file__, {'_WORK_BOOTSTRAP': bootstrap}, '__work__')
            process = context.Process(target=target, args=args, name=name)
            process.start()
            self.process = process
            output.close()
            self.started.set()
            reader = threading.Thread(target=self._read, args=(incoming,), name=f'{name}-reader', daemon=True)
            try:
                reader.start()
                while process.exitcode is None and not self.stop.wait(.02):
                    pass
            finally:
                self._reap(process, cancelled)
                if reader.ident is not None:
                    reader.join()
            event, self._terminal = self._terminal, None
            if not self.stop.is_set():
                if event is None:
                    event = {'kind': 'error', 'message': f'Worker exited ({process.exitcode}) without a result'}
                self._deliver(event)

    def _read(self, incoming):
        try:
            while True:
                event = incoming.recv()
                if event['kind'] in TERMINAL:
                    self._terminal = event
                    return
                self._deliver(event)
        except EOFError:
            return
        except Exception as error:  # noqa: BLE001 (a transport failure must reach the owner)
            self._terminal = error_event(error)

    def _reap(self, process, cancelled):
        if not process.is_alive():
            return
        cancelled.set()
        process.join(GRACE)
        for stop in (process.terminate, process.kill):
            if not process.is_alive():
                return
            stop()
            process.join(JOIN_TIMEOUT)
        if process.is_alive():
            self.shutdown_error = RuntimeError(f'Worker {process.pid} did not stop')
            raise self.shutdown_error


class Runner:
    def __init__(self):
        self._lock = threading.Lock()
        self._runs = set()
        self._shutdown_errors = []

    def start(self, function, arguments, name, deliver):
        run = Run(self, function, arguments, name, deliver)
        with self._lock:
            self._runs.add(run)
        try:
            run.thread.start()
        except RuntimeError:
            self.finished(run)
            raise
        return run

    def finished(self, run):
        with self._lock:
            self._runs.remove(run)
            if run.shutdown_error is not None:
                self._shutdown_errors.append(run.shutdown_error)

    def close(self):
        with self._lock:
            runs = tuple(self._runs)
        for run in runs:
            run.stop.set()
        for run in runs:
            run.thread.join()
        if self._shutdown_errors:
            raise self._shutdown_errors[0]


if __name__ == '__work__':
    _bootstrap(*globals()['_WORK_BOOTSTRAP'])
