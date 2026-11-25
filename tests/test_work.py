# SPDX-License-Identifier: GPL-3.0-or-later
"""Process lifecycle without a toolkit, also when adopted by another package."""
import ctypes
import os
import threading
import time
import unittest

import _setup


def echo(value, *, context):
    context.progress(1, 1)
    return {'value': value, 'pid': os.getpid()}


def wait_for_cancel(*, context):
    while True:
        context.check_cancelled()
        time.sleep(.002)


def fail(*, context):
    raise ValueError('synthetic failure')


def exit_without_result(*, context):
    os._exit(17)


def return_value(value, *, context):
    return value


def ignore_cancel(*, context):
    context.progress(1, 1)
    threading.Event().wait(60)


def large_result(*, context):
    return bytes(32 * 1024 * 1024)


_decoding = threading.Event()
_release_decoder = threading.Event()


def decode_result(data):
    _decoding.set()
    if not _release_decoder.wait(10):
        raise TimeoutError('fixture did not release the decoder')
    return data


class InTransit:
    def __reduce__(self):
        return decode_result, (bytes(32 * 1024 * 1024),)


def result_in_transit(*, context):
    return InTransit()


def partial_results(*, context):
    context.progress(1, 4, 'work')
    context.partial('chunk', 'first')
    context.progress(3, 4, 'work')
    context.partial('chunk', 'latest')
    return 'done'


def pid_alive(pid):
    """Ask the OS whether this PID still denotes a running process."""
    if os.name != 'nt':
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return False
        return True
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.OpenProcess.argtypes = (ctypes.c_ulong, ctypes.c_int, ctypes.c_ulong)
    kernel.OpenProcess.restype = ctypes.c_void_p
    kernel.WaitForSingleObject.argtypes = (ctypes.c_void_p, ctypes.c_ulong)
    kernel.WaitForSingleObject.restype = ctypes.c_ulong
    kernel.CloseHandle.argtypes = (ctypes.c_void_p,)
    kernel.CloseHandle.restype = ctypes.c_int
    handle = kernel.OpenProcess(0x00100000, False, pid)  # SYNCHRONIZE
    if not handle:
        if ctypes.get_last_error() == 87:  # ERROR_INVALID_PARAMETER: unknown PID
            return False
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        state = kernel.WaitForSingleObject(handle, 0)
        if state not in (0, 258):  # WAIT_OBJECT_0 or WAIT_TIMEOUT
            raise ctypes.WinError(ctypes.get_last_error())
        return state == 258
    finally:
        kernel.CloseHandle(handle)


class WorkTests(unittest.TestCase):
    def finish(self, job):
        end = time.monotonic() + 10
        events = []
        while job.busy and time.monotonic() < end:
            events.extend(job.poll())
            time.sleep(.005)
        self.assertFalse(job.busy)
        return events

    def test_result_progress_and_process(self):
        with _setup.shared('app.work').Job(echo, (42,), name='fake-worker') as job:
            events = self.finish(job)
            self.assertEqual(job.status, 'completed')
            self.assertEqual(job.result['value'], 42)
            self.assertNotEqual(job.result['pid'], os.getpid())
            self.assertTrue(any(event['kind'] == 'progress' for event in events))

    def test_cancel_and_error(self):
        Job = _setup.shared('app.work').Job
        with Job(wait_for_cancel, name='fake-cancel') as job:
            job.cancel()
            self.finish(job)
            self.assertEqual(job.status, 'cancelled')
        with Job(fail, name='fake-error') as job:
            self.finish(job)
            self.assertEqual(job.status, 'error')
            self.assertIn('synthetic failure', job.error)

    def test_close_reaps_process_and_is_idempotent(self):
        job = _setup.shared('app.work').Job(wait_for_cancel, name='fake-close')
        process = job.process
        pid = job.pid
        job.close()
        job.close()
        self.assertFalse(process.is_alive())
        self.assertFalse(pid_alive(pid))
        self.assertFalse(job.busy)

    def test_cancel_reports_completion_only_after_the_process_exits(self):
        Job = _setup.shared('app.work').Job
        with Job(ignore_cancel, name='fake-force-cancel') as job:
            deadline = time.monotonic() + 10
            while not job.poll() and time.monotonic() < deadline:
                time.sleep(.005)
            pid = job.pid
            self.assertTrue(pid_alive(pid))
            job.cancel()
            self.assertEqual(self.finish(job), [{'kind': 'cancelled'}])
            self.assertFalse(pid_alive(pid))


class CenterTests(unittest.TestCase):
    def setUp(self):
        self.now = 0.0
        self.wake = threading.Event()
        self.events = []
        self.owner = threading.get_ident()
        self.notifications = 0
        self.center = _setup.shared('app.work').Center(post=self.post, clock=lambda: self.now)
        self.addCleanup(self.center.close)

    def post(self):
        self.notifications += 1
        self.wake.set()

    def deliver(self, event):
        self.assertEqual(threading.get_ident(), self.owner)
        self.events.append(event)

    def submit(self, function, arguments=(), **options):
        return self.center.submit(function, arguments, name='fixture', on_event=self.deliver, **options)

    def until(self, predicate, *, pump=True):
        deadline = time.monotonic() + 10
        while not predicate() and time.monotonic() < deadline:
            if pump:
                self.center.pump()
            self.wake.wait(.01)
            self.wake.clear()
        self.assertTrue(predicate())

    def test_reused_slot_filters_result_already_in_the_queue(self):
        old = self.submit(return_value, ('obsolete',), slot='document')
        self.assertTrue(self.wake.wait(10), 'first result must be pending delivery')
        new = self.submit(return_value, ('latest',), slot='document')
        self.until(lambda: not new.busy)
        self.assertEqual(self.events, [{'kind': 'completed', 'result': 'latest'}])
        self.assertEqual(old.status, 'cancelled')
        self.assertFalse(pid_alive(old.pid))
        self.assertFalse(pid_alive(new.pid))

    def test_queued_input_is_built_after_the_last_change(self):
        value = ['original']
        inputs = []

        def build():
            inputs.append(value[0])
            return (value[0],)

        handle = self.submit(return_value, build=build, settle=5, topics=('document',))
        self.assertEqual(self.center.rows()[0]['state'], 'queued')
        self.now = 4
        value[0] = 'updated'
        self.center.changed(('document:selection',))
        self.now = 5
        self.center.pump()
        self.assertIsNone(handle.pid)
        self.now = 9
        self.until(lambda: not handle.busy)
        self.assertEqual(inputs, ['updated'])
        self.assertEqual(self.events, [{'kind': 'completed', 'result': 'updated'}])
        self.assertFalse(pid_alive(handle.pid))

    def test_change_discards_a_queued_result_without_a_fresh_builder(self):
        handle = self.submit(return_value, ('obsolete',), topics=('document',))
        self.assertTrue(self.wake.wait(10), 'result must be pending delivery')
        self.center.changed(('file',))
        self.center.pump()
        self.assertEqual(handle.status, 'cancelled')
        self.assertEqual(self.events, [])
        self.assertFalse(pid_alive(handle.pid))

    def test_worker_exception_and_unexpected_exit_are_delivered_once(self):
        for function, message in ((fail, 'ValueError: synthetic failure'), (exit_without_result, '17')):
            with self.subTest(function=function.__name__):
                handle = self.submit(function)
                self.until(lambda handle=handle: not handle.busy)
                self.assertEqual(handle.status, 'error')
                self.assertIn(message, handle.error)
                self.assertFalse(pid_alive(handle.pid))
        self.assertEqual([event['kind'] for event in self.events], ['error', 'error'])

    def test_cancel_before_launch_does_not_build_or_create_a_process(self):
        handle = self.submit(return_value, build=lambda: self.fail('cancelled request was built'), settle=1)
        handle.cancel()
        self.now = 2
        self.center.pump()
        self.assertIsNone(handle.pid)
        self.assertEqual(handle.status, 'cancelled')
        self.assertEqual(self.center.rows(), [])
        self.assertEqual(self.events, [])

    def test_cancel_after_launch_reaps_an_uncooperative_process_without_pumping(self):
        handle = self.submit(ignore_cancel)
        self.until(lambda: bool(self.events))
        self.assertEqual(self.events[0]['kind'], 'progress')
        pid = handle.pid
        self.assertTrue(pid_alive(pid))
        handle.cancel()
        self.until(lambda: not pid_alive(pid), pump=False)
        self.center.pump()
        self.assertEqual(len(self.events), 1)
        self.assertEqual(handle.status, 'cancelled')

    def test_close_discards_large_result_waiting_for_delivery(self):
        handle = self.submit(large_result)
        self.assertTrue(self.wake.wait(10), '32 MiB result must be pending delivery')
        pid = handle.pid
        self.center.close()
        notifications = self.notifications
        self.assertFalse(self.center.pump())
        self.center.close()
        self.assertEqual(self.events, [])
        self.assertEqual(self.notifications, notifications)
        self.assertFalse(pid_alive(pid))

    def test_close_while_a_large_result_is_being_decoded(self):
        _decoding.clear()
        _release_decoder.clear()
        self.addCleanup(_release_decoder.set)
        handle = self.submit(result_in_transit)
        self.assertTrue(_decoding.wait(10), 'reader must be decoding 32 MiB')
        self.assertFalse(self.center.pump())
        self.assertTrue(handle.busy)
        pid = handle.pid

        # Release the reader only once close has invalidated deliveries.
        def release_after_close():
            deadline = time.monotonic() + 10
            while not self.center._closed and time.monotonic() < deadline:
                _release_decoder.wait(.01)
            _release_decoder.set()

        releaser = threading.Thread(target=release_after_close)
        releaser.start()
        self.center.close()
        releaser.join()
        self.assertEqual(self.events, [])
        self.assertEqual(self.notifications, 0)
        self.assertFalse(pid_alive(pid))

    def test_progress_and_partials_are_delivered_in_budgeted_turns(self):
        handle = self.submit(partial_results)
        self.assertTrue(self.wake.wait(10))
        self.until(lambda: not handle._run.thread.is_alive(), pump=False)
        self.assertTrue(self.center.pump(budget=0))
        self.assertEqual(self.center.rows()[0]['fraction'], .75)
        self.assertIs(self.center.find(handle.id), handle)
        self.until(lambda: not handle.busy)
        self.assertEqual(self.events, [
            {'kind': 'progress', 'current': 3, 'total': 4, 'message': 'work'},
            {'kind': 'partial', 'key': 'chunk', 'data': 'latest'},
            {'kind': 'completed', 'result': 'done'},
        ])
        self.assertIsNone(self.center.find(handle.id))
        self.assertFalse(pid_alive(handle.pid))
