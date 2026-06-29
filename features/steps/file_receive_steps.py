"""Steps for file_receive feature tests (lidi-receive → lidi-file-receive edge cases)."""

import os
import signal
import subprocess
import threading
import time

from behave import given, when, then, use_step_matcher
from features.steps.lidi import (
    start_diode_no_file_receive,
    start_lidi_file_receive,
    start_throttled_diode,
    start_throttled_diode_no_file_receive,
)

use_step_matcher("parse")


# ---------------------------------------------------------------------------
# Given — diode startup variants (receiver-side configurations)
# ---------------------------------------------------------------------------

@given('lidi is started without lidi-file-receive and limited to {bandwidth}')
def step_start_without_file_receive_throttled(context, bandwidth):
    """Start lidi-receive + lidi-send with bandwidth limit but no lidi-file-receive."""
    start_throttled_diode_no_file_receive(context, bandwidth)


@given('lidi is started without lidi-file-receive, with max_clients {n:d} and limited to {bandwidth}')
def step_start_without_file_receive_with_clients(context, n, bandwidth):
    """Start lidi-receive + lidi-send with explicit max_clients but no lidi-file-receive."""
    context.max_clients = n
    start_throttled_diode_no_file_receive(context, bandwidth)


@given('lidi-file-receive is started with max_files set to {n:d}')
def step_start_file_receive_max_files(context, n):
    """Start lidi-file-receive that exits after receiving n files."""
    context.receive_file_max_files = n
    start_lidi_file_receive(context)


@given('lidi-receive is configured with queue_size of {n:d}')
def step_configure_queue_size(context, n):
    """Configure queue_size before the diode is started (must precede the start step)."""
    context.queue_size = n


@given('lidi-file-receive output directory is read-only')
def step_make_output_dir_readonly(context):
    """Remove write permission from receive_dir so lidi-file-receive cannot create files.

    lidi-file-receive calls fs::OpenOptions::open() when a transfer arrives; with 0o555
    on the directory, that call fails with EACCES, which closes the connection.
    environment.py after_scenario restores permissions before cleanup.
    """
    os.chmod(context.receive_dir, 0o555)
    context._receive_dir_was_readonly = True


# ---------------------------------------------------------------------------
# When — actions on the running lidi-file-receive process
# ---------------------------------------------------------------------------

@when('lidi-file-receive is killed after {seconds:d} seconds')
def step_kill_file_receive_delayed(context, seconds):
    """Kill lidi-file-receive with SIGKILL after N seconds (background thread).

    SIGKILL closes the TCP socket → EPIPE on lidi-receive's next write_all()
    → client worker exits → slot freed in the pre-allocated worker pool.
    """
    proc = getattr(context, 'proc_lidi_receive_file', None)
    if proc is None:
        raise Exception("lidi-file-receive is not running")

    def _kill():
        time.sleep(seconds)
        if proc.poll() is None:
            proc.kill()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pass

    threading.Thread(target=_kill, daemon=True).start()


@when('lidi-file-receive is suspended after {seconds:d} seconds')
def step_suspend_file_receive(context, seconds):
    """Send SIGSTOP to lidi-file-receive after N seconds (background thread).

    SIGSTOP suspends the process without closing its TCP connection.
    lidi-file-receive stops reading → OS TCP receive buffer fills →
    TCP flow control stalls → write_all() in lidi-receive blocks.
    environment.py after_scenario sends SIGCONT before killing the process.
    """
    proc = getattr(context, 'proc_lidi_receive_file', None)
    if proc is None:
        raise Exception("lidi-file-receive is not running")

    def _suspend():
        time.sleep(seconds)
        if proc.poll() is None:
            try:
                os.kill(proc.pid, signal.SIGSTOP)
                context._file_receive_suspended = True
            except ProcessLookupError:
                pass

    threading.Thread(target=_suspend, daemon=True).start()


@when('lidi-file-receive is started {seconds:d} seconds later')
def step_start_file_receive_late(context, seconds):
    """Sleep N seconds then start lidi-file-receive (simulates late startup)."""
    time.sleep(seconds)
    start_lidi_file_receive(context)


@when('{seconds:d} seconds are waited for slot release')
def step_wait_for_slot_release(context, seconds):
    """Wait N seconds for lidi-receive to detect broken pipe and free the worker slot."""
    time.sleep(seconds)


# ---------------------------------------------------------------------------
# Then — assertions
# ---------------------------------------------------------------------------

@then('lidi-receive should still be running')
def step_lidi_receive_still_running(context):
    """Assert that the lidi-receive process has not exited."""
    proc = getattr(context, 'proc_lidi_receive', None)
    if proc is None:
        raise Exception("lidi-receive was never started")
    rc = proc.poll()
    if rc is not None:
        raise Exception(f"lidi-receive has exited unexpectedly with return code {rc}")


@then('lidi-file-receive should have exited')
def step_file_receive_exited(context):
    """Assert that lidi-file-receive has stopped running within 5 seconds."""
    proc = getattr(context, 'proc_lidi_receive_file', None)
    if proc is None:
        return
    deadline = time.time() + 5
    while time.time() < deadline:
        if proc.poll() is not None:
            return
        time.sleep(0.1)
    raise Exception("lidi-file-receive is still running but should have exited")
