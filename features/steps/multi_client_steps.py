"""Steps for multi-client (max_clients) feature tests."""

from behave import given, when, then, use_step_matcher
import os
import subprocess
import time
import threading
from features.steps.lidi import (
    start_diode, start_throttled_diode, start_lidi_send, start_lidi_receive
)
from features.steps.file import create_file, test_file
from features.steps.config import build_lidi_send_file_command
from features.steps.utils import PROCESS_READY_DELAY

use_step_matcher("parse")


@given('abort_timeout is set to {seconds:d} second')
def step_set_abort_timeout(context, seconds):
    """Set abort_timeout for the test."""
    context.abort_timeout = seconds


@given('lidi is started with max_clients set to {max_clients:d}')
def step_start_lidi_with_max_clients(context, max_clients):
    """Start lidi with specified max_clients."""
    context.max_clients = max_clients
    start_diode(context)


@given('lidi is started with max_clients set to {max_clients:d} and limited to {bandwidth}')
def step_start_lidi_with_max_clients_and_bandwidth(context, max_clients, bandwidth):
    """Start lidi with max_clients and bandwidth limitation."""
    context.max_clients = max_clients
    start_throttled_diode(context, bandwidth)


@when('file "{name}" of size {size} is sent')
def step_send_file(context, name, size):
    """Send a single file."""
    from features.steps.lidi import send_file_command

    filename = os.path.join(context.send_dir, name)
    create_file(context, filename, size)
    send_file_command(context, filename, background=False)


@when('{n:d} clients are launched concurrently sending "{names}" of size {size} each')
def step_concurrent_clients(context, n, names, size):
    """Launch n concurrent clients."""
    if not hasattr(context, 'concurrent_processes'):
        context.concurrent_processes = []

    # Parse client names
    if ',' in names:
        client_names = [s.strip().strip('"') for s in names.split(',')]
    else:
        client_names = [f"{names}_{i+1}" for i in range(n)]

    # Create and send files concurrently
    for client_name in client_names:
        filename = os.path.join(context.send_dir, client_name)
        create_file(context, filename, size)

        cmd = build_lidi_send_file_command(context, filename)
        proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        context.concurrent_processes.append({
            'name': client_name,
            'process': proc,
            'started': time.time()
        })
        time.sleep(0.1)


@when('{n:d} clients are launched concurrently sending files of size {size} each')
def step_concurrent_clients_generic(context, n, size):
    """Launch n concurrent clients with auto-generated names."""
    if not hasattr(context, 'concurrent_processes'):
        context.concurrent_processes = []

    for i in range(n):
        client_name = f"input_{i+1}"
        filename = os.path.join(context.send_dir, client_name)
        create_file(context, filename, size)

        cmd = build_lidi_send_file_command(context, filename)
        proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        context.concurrent_processes.append({
            'name': client_name,
            'process': proc,
            'started': time.time()
        })
        time.sleep(0.1)


@when('client {client_num:d} starts sending "{name}" of size {size}')
def step_client_start_sending(context, client_num, name, size):
    """Start a client sending in background."""
    if not hasattr(context, 'concurrent_processes'):
        context.concurrent_processes = []

    filename = os.path.join(context.send_dir, name)
    create_file(context, filename, size)

    cmd = build_lidi_send_file_command(context, filename)
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    context.concurrent_processes.append({
        'name': name,
        'process': proc,
        'started': time.time(),
        'client_num': client_num
    })


@when('client {client_num:d} is killed after {seconds:d} seconds')
def step_kill_client(context, client_num, seconds):
    """Kill a specific concurrent client after N seconds."""
    if not hasattr(context, 'concurrent_processes') or not context.concurrent_processes:
        raise Exception("No concurrent processes to kill")

    idx = client_num - 1
    if idx >= len(context.concurrent_processes):
        raise Exception(f"Client {client_num} does not exist")

    proc_info = context.concurrent_processes[idx]

    def kill_after_delay():
        time.sleep(seconds)
        if proc_info['process'].poll() is None:
            proc_info['process'].terminate()
            try:
                proc_info['process'].wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc_info['process'].kill()
                proc_info['process'].wait()

    kill_thread = threading.Thread(target=kill_after_delay, daemon=True)
    kill_thread.start()


@when('clients {client_range} are killed after {seconds:d} seconds')
def step_kill_clients_range(context, client_range, seconds):
    """Kill multiple concurrent clients after N seconds."""
    if '-' not in client_range:
        raise Exception("Expected client range like '2-6'")

    parts = client_range.split('-')
    start = int(parts[0])
    end = int(parts[1])

    if not hasattr(context, 'concurrent_processes') or not context.concurrent_processes:
        raise Exception("No concurrent processes to kill")

    def kill_after_delay():
        time.sleep(seconds)
        for client_num in range(start, end + 1):
            idx = client_num - 1
            if idx < len(context.concurrent_processes):
                proc_info = context.concurrent_processes[idx]
                if proc_info['process'].poll() is None:
                    proc_info['process'].terminate()
                    try:
                        proc_info['process'].wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        proc_info['process'].kill()
                        proc_info['process'].wait()

    kill_thread = threading.Thread(target=kill_after_delay, daemon=True)
    kill_thread.start()


@when('{n:d} additional clients start sending "{pattern}" of size {size} each')
def step_additional_clients(context, n, pattern, size):
    """Start additional clients with name pattern."""
    if not hasattr(context, 'concurrent_processes'):
        context.concurrent_processes = []

    for i in range(n):
        name = pattern.replace('*', str(i + 1))
        filename = os.path.join(context.send_dir, name)
        create_file(context, filename, size)

        cmd = build_lidi_send_file_command(context, filename)
        proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        context.concurrent_processes.append({
            'name': name,
            'process': proc,
            'started': time.time()
        })
        time.sleep(0.1)


@when('{seconds:d} seconds are waited for Abort propagation')
def step_wait_abort(context, seconds):
    """Wait for Abort propagation."""
    time.sleep(seconds)


@when('{n:d} sequential file transfers of "{names}" of size {size} are executed')
def step_sequential_transfers(context, n, names, size):
    """Execute sequential file transfers."""
    from features.steps.lidi import send_file_command

    if ',' in names:
        client_names = [s.strip().strip('"') for s in names.split(',')]
    else:
        client_names = [f"{names}_{i+1}" for i in range(n)]

    for client_name in client_names:
        filename = os.path.join(context.send_dir, client_name)
        create_file(context, filename, size)
        send_file_command(context, filename, background=False)


@then('lidi-file-receive file "{name}" in {seconds:d} seconds')
def step_file_received(context, name, seconds):
    """Verify that a file was received."""
    test_file(context, context.receive_dir, name, seconds)


@then('file "{name}" should not exist after {seconds:d} seconds')
def step_file_not_received(context, name, seconds):
    """Verify that a file was NOT received."""
    start_time = time.time()
    while time.time() - start_time < seconds:
        output_path = os.path.join(context.receive_dir, name)
        if os.path.exists(output_path):
            raise Exception(f"File {name} was received but should not have been")
        time.sleep(0.1)


@then('file "{name}" should not be received')
def step_file_not_present(context, name):
    """Verify that a file does not exist.

    An aborted transfer is only cleaned up once lidi-receive-file detects the
    incomplete stream, which can happen slightly after the previous step
    completes. Allow a short grace period for that cleanup before failing.
    """
    output_path = os.path.join(context.receive_dir, name)
    deadline = time.time() + 30
    while os.path.exists(output_path) and time.time() < deadline:
        time.sleep(0.1)
    if os.path.exists(output_path):
        raise Exception(f"File {name} exists but should not")


@then('lidi-file-receive log should report an error for an incomplete transfer')
def step_log_reports_incomplete_transfer_error(context):
    """Verify that lidi-file-receive logged an error for the interrupted transfer.

    The error is logged right after the partial file is removed, so allow a
    short grace period for the log line to be flushed.
    """
    log_path = os.path.join(context.log_dir, "lidi_receive_file.log")
    deadline = time.time() + 45
    content = ""
    while time.time() < deadline:
        if os.path.exists(log_path):
            with open(log_path) as f:
                content = f.read()
            if "ERROR" in content and "invalid file size" in content:
                return
        time.sleep(0.2)

    raise Exception(
        f"lidi-file-receive log does not report an 'invalid file size' error "
        f"for the incomplete transfer; log content:\n{content}"
    )


@then('all {n:d} output files exist and are identical within {seconds:d} seconds')
def step_all_files_received(context, n, seconds):
    """Verify that all output files were received."""
    for i in range(n):
        name = f"input_{i+1}"
        test_file(context, context.receive_dir, name, seconds)


@then('all 5 additional output files exist and are identical within {seconds:d} seconds')
def step_all_5_additional_files(context, seconds):
    """Verify that all 5 additional output files were received."""
    if not hasattr(context, 'concurrent_processes'):
        raise Exception("No concurrent processes")

    # Skip the first process (main large transfer) and test the 5 additional ones
    for proc_info in context.concurrent_processes[1:6]:
        name = proc_info['name']
        test_file(context, context.receive_dir, name, seconds)


def _parse_size(size_str):
    """Parse size string (e.g., '100KB', '1MB') to bytes."""
    size_str = size_str.strip()

    # Handle numeric values (assumed to be in bytes)
    if size_str.isdigit():
        return int(size_str)

    # Handle unit-based sizes
    units = {
        'B': 1,
        'KB': 1024,
        'MB': 1024 ** 2,
        'GB': 1024 ** 3,
    }

    for unit, multiplier in units.items():
        if size_str.endswith(unit):
            try:
                number = int(size_str[:-len(unit)])
                return number * multiplier
            except ValueError:
                pass

    raise ValueError(f"Cannot parse size: {size_str}")


@given('lidi-send fails to start with max_clients set to {max_clients:d}')
def step_lidi_send_fails_to_start(context, max_clients):
    """Verify that lidi-send fails to start with max_clients=0."""
    context.max_clients = max_clients
    context.no_prometheus = True
    try:
        start_lidi_send(context, capture_output=True)
        raise Exception(f"lidi-send should have failed to start with max_clients={max_clients}, but it started successfully")
    except Exception as e:
        error_msg = str(e)
        if "max_clients must be greater than 0" not in error_msg:
            raise Exception(f"lidi-send failed, but not with expected error about max_clients. Error was: {error_msg}")
    finally:
        # Clean up the flag for next tests
        context.no_prometheus = False


@given('lidi-receive fails to start with max_clients set to {max_clients:d}')
def step_lidi_receive_fails_to_start(context, max_clients):
    """Verify that lidi-receive fails to start with max_clients=0."""
    context.max_clients = max_clients
    context.no_prometheus = True
    try:
        start_lidi_receive(context, capture_output=True)
        raise Exception(f"lidi-receive should have failed to start with max_clients={max_clients}, but it started successfully")
    except Exception as e:
        error_msg = str(e)
        if "max_clients must be greater than 0" not in error_msg:
            raise Exception(f"lidi-receive failed, but not with expected error about max_clients. Error was: {error_msg}")
    finally:
        # Clean up the flag for next tests
        context.no_prometheus = False
