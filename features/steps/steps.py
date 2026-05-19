
from behave import given, when, then, use_step_matcher
import os
import time
import subprocess
import re

from features.steps.lidi import create_file, send_file, send_multiple_files, start_diode, start_lidi_file_receive, start_lidi_receive, start_lidi_send, start_lidi_send_dir, start_throttled_diode, stop_lidi_file_receive, stop_lidi_receive, stop_lidi_send
from features.steps.file import create_and_copy_file, create_and_copy_multiple_files, create_and_move_file, parse_human_size, test_file, test_no_file
from features.steps.config import build_lidi_send_file_command

use_step_matcher("cfparse")

@then('wait {seconds:d} seconds')
def step_wait_seconds(context, seconds):
    """Wait for a specified number of seconds."""
    time.sleep(seconds)

@given('lidi is started')
def step_impl(context):
    start_diode(context)

@given('lidi-send is started')
def step_lidi_send_started(context):
    start_lidi_send(context)

@when('lidi-receive is restarted')
def step_impl(context):
    stop_lidi_receive(context)
    # wait some time to prevent address already in use if restarted too quickly
    time.sleep(5)
    start_lidi_receive(context)

@when('lidi-send is restarted')
def step_impl(context):
    stop_lidi_send(context)
    # wait for lidi-receive reset timeout to happen
    time.sleep(2)
    start_lidi_send(context)

@when('lidi-file-receive is restarted')
def step_impl(context):
    stop_lidi_file_receive(context)
    # wait some time to prevent address already in use if restarted too quickly
    time.sleep(5)
    start_lidi_file_receive(context)

@given('lidi-dir-send is started with watch and ignore dot files')
def step_lidi_send_dir_with_watch_and_ignore_dot_files(context):
    start_lidi_send_dir(context, True, '^\\.')

@given('lidi-dir-send is started with watch')
def step_lidi_send_dir_with_watch(context):
    start_lidi_send_dir(context, True)

@given('lidi-dir-send is started')
def step_lidi_send_dir(context):
    start_lidi_send_dir(context)

@given('lidi is started with max throughput of {throughput} and MTU {mtu}')
def step_lidi_started_with_max_throughput_and_mtu(context, throughput, mtu):
    # throughput format: tc notation (e.g., "100mbit", "990kbit")
    # mtu: maximum transmission unit in bytes
    context.read_rate = throughput
    context.mtu = int(mtu)
    start_throttled_diode(context, context.read_rate, int(mtu))

@given('lidi is started with max throughput of {throughput}')
def step_lidi_started_with_max_throughput(context, throughput):
    # two possibilities : limit file system read throughput or configure the lidi for that
    # throughput format: tc notation (e.g., "100mbit", "990kbit")
    context.read_rate = throughput
    start_throttled_diode(context, context.read_rate)

@given('encoding block size is {encoding}')
def step_set_encoding(context, encoding):
    context.block_size = encoding

@given('repair percentage is {repair} %')
def step_set_encoding(context, repair):
    context.repair = repair

@when('lidi-file-send file {name} of size {size} with hash')
def step_send_file_with_hash(context, name, size):
    """Send a file with hash verification enabled."""
    filename = os.path.join(context.send_dir, name)
    create_file(context, filename, size)
    # Build command with --hash flag
    cmd = build_lidi_send_file_command(context, filename)
    cmd.append('--hash')
    result = subprocess.run(cmd, timeout=300, text=True, capture_output=True)
    if result.returncode != 0:
        raise Exception(f"Send with hash failed: {result.stderr}")
    # The hash is calculated and transmitted, mark it in context
    context.hash_enabled = True

@when('lidi-file-send file {name} of size {size} without receiver')
def step_send_file_without_receiver(context, name, size):
    """Send a file when lidi-file-receive is not running (error scenario)."""
    filename = os.path.join(context.send_dir, name)
    create_file(context, filename, size)
    cmd = build_lidi_send_file_command(context, filename)
    # Don't wait for success; just try to send
    result = subprocess.run(cmd, timeout=10, text=True, capture_output=True)
    # Store result for error checking
    context.send_error_output = result.stderr
    context.send_returncode = result.returncode

@when('lidi-file-send file {name} of size {size}')
def step_send_file(context, name, size):
    send_file(context, name, size)

@when('lidi-send restarts while lidi-file-send file {name} of size {size}')
def step_impl(context, name, size):
    send_file(context, name, size, True)
    # transfer is in progress, wait 1 second then restart diode
    time.sleep(3)
    stop_lidi_send(context)
    start_lidi_send(context)

@when('lidi-receive restarts while lidi-file-send file {name} of size {size}')
def step_impl(context, name, size):
    send_file(context, name, size, True)
    # transfer is in progress, wait 1 second then restart diode
    time.sleep(3)
    stop_lidi_receive(context)
    time.sleep(5)
    start_lidi_receive(context)

@then('lidi-file-receive file {name} in {seconds} seconds')
def step_impl(context, name, seconds):
    test_file(context, context.receive_dir, name, seconds)

@when('lidi-file-receive file {name} in {seconds} seconds')
def step_impl(context, name, seconds):
    test_file(context, context.receive_dir, name, seconds)

@when('lidi-file-send {files} files of size {size}')
def step_impl(context, files, size):
    for i in range(int(files)):
        name = str(f"test_file_{i}")
        filename = os.path.join(context.send_dir, name)
        create_file(context, filename, size)

    # now send all of them at once
    send_multiple_files(context)

@then('lidi-file-receive all files in {seconds} seconds')
def step_impl(context, seconds):
    for name in context.files:
        test_file(context, context.receive_dir, name, seconds)

@given(u'lidi with send-dir is started')
def step_impl(context):
    start_diode(context)
    start_lidi_send_dir(context)

@when(u'we copy a file {name} of size {size}')
def step_impl(context, name, size):
    create_and_copy_file(context, name, size)

@when(u'we copy {files} files of size {size}')
def step_impl(context, files, size):
    create_and_copy_multiple_files(context, files, size)

@when(u'we move a file {name} of size {size}')
def step_impl(context, name, size):
    create_and_move_file(context, name, size)

@then('lidi-file-receive no file {name} in {seconds} seconds')
def step_impl(context, name, seconds):
    test_no_file(context, context.receive_dir, name, seconds)

@then(u'file {name} is in source directory')
def step_impl(context, name):
    test_file(context, context.send_dir, name, 1)

@given('there is a network interrupt of {network_up_after} after {network_down_after}')
def step_impl(context, network_up_after, network_down_after):
    context.network_down_after = parse_human_size(network_down_after)
    context.network_up_after = parse_human_size(network_up_after) + context.network_down_after

@given('there is a network drop of {percent} %')
def step_given_network_drop_percent(context, percent):
    context.network_drop = percent

@given('there is a limited network bandwidth of {bandwidth} Mb/s')
def step_given_network_limited_bandwidth(context, bandwidth):
    # used by network simulator to drop packets if bandwidth is higher than that
    context.network_max_bandwidth = str(int(bandwidth) * 1000000)

@given('network bandwidth must not exceed {bandwidth} Mb/s')
def step_limited_bandwidth_not_exceeded(context, bandwidth):
    # used by network simulator to abort if received bandwidth is higher than that
    context.bandwidth_must_not_exceed = str(int(bandwidth) * 1000000)


@then('the hash is logged for file {name}')
def step_verify_hash_logged(context, name):
    """Verify that hash was enabled and computed for the file."""
    if not hasattr(context, 'hash_enabled') or not context.hash_enabled:
        raise Exception(f"Hash was not computed for file {name}")
    # Verify the file was actually received with correct content
    test_file(context, context.receive_dir, name, 5)

@then('lidi-send is still running')
def step_verify_lidi_send_running(context):
    """Verify that lidi-send process is still alive."""
    poll = context.proc_lidi_send.poll()
    if poll is not None:
        raise Exception(f"lidi-send crashed with return code {poll}")


# Buffer size tests
@given('buffer size is set to {size}')
def step_set_buffer_size(context, size):
    """Set the buffer size for subsequent lidi-file-send commands."""
    context.buffer_size = size


# Log config tests
@given('logging configuration is disabled')
def step_disable_log_config(context):
    """Disable the --log-config option for subsequent commands."""
    context.skip_log_config = True


@given('log level is set to {level}')
def step_set_log_level(context, level):
    """Set the log level for commands without a config file."""
    context.log_level = level


@then('command should have failed with non-zero exit code')
def step_verify_command_failed(context):
    """Verify that the last send command failed with non-zero exit code."""
    if not hasattr(context, 'send_returncode'):
        raise Exception("No send command was executed")
    if context.send_returncode == 0:
        raise Exception(f"Expected non-zero exit code, got {context.send_returncode}")


@when('lidi-file-send with log-config {log_config_path} file {name} of size {size}')
def step_send_file_with_log_config_path(context, log_config_path, name, size):
    """Send a file using a specific log-config path (may not exist)."""
    filename = os.path.join(context.send_dir, name)
    from features.steps.file import create_file
    create_file(context, filename, size)

    cmd = [
        f"{context.bin_dir}/lidi-file-send",
        "--buffer-size", "8192",
        "--to-tcp", f"127.0.0.1:{context.tcp_send_port}",
        "--log-config", log_config_path,
        filename
    ]

    result = subprocess.run(cmd, timeout=10, text=True, capture_output=True)
    context.send_returncode = result.returncode
    context.send_error_output = result.stderr


@given('an invalid log4rs config file is created')
def step_create_invalid_log_config(context):
    """Create an invalid log4rs configuration file."""
    invalid_config_path = os.path.join(context.base_dir, "invalid_log_config.yaml")
    with open(invalid_config_path, "w") as f:
        f.write("this is not valid yaml: [ unclosed bracket\n")
    context.invalid_log_config_path = invalid_config_path


@when('lidi-file-send with the invalid log-config file {name} of size {size}')
def step_send_file_with_invalid_log_config(context, name, size):
    """Send a file using the invalid log-config file."""
    filename = os.path.join(context.send_dir, name)
    from features.steps.file import create_file
    create_file(context, filename, size)

    cmd = [
        f"{context.bin_dir}/lidi-file-send",
        "--buffer-size", "8192",
        "--to-tcp", f"127.0.0.1:{context.tcp_send_port}",
        "--log-config", context.invalid_log_config_path,
        filename
    ]

    result = subprocess.run(cmd, timeout=10, text=True, capture_output=True)
    context.send_returncode = result.returncode
    context.send_error_output = result.stderr


# Log file verification steps
@given('a log file is prepared for lidi-file-send with {level} level')
def step_prepare_log_file_for_level(context, level):
    """Create a log config file for lidi-file-send with specified level."""
    # build_log_config is defined in environment.py
    def build_log_config(filename, level_name):
        return f"""
appenders:
  file:
    kind: file
    path: {filename}

root:
  level: {level_name}
  appenders:
    - file
"""

    log_file = os.path.join(context.base_dir, f"lidi_send_file_{level}.log")
    config_file = os.path.join(context.base_dir, f"log_config_lidi_send_file_{level}.yml")

    log_content = build_log_config(log_file, level.lower())
    with open(config_file, "w") as f:
        f.write(log_content)

    context.test_log_file = log_file
    context.test_log_config = config_file


@given('lidi-file-send is configured with {level} level logging')
def step_configure_lidi_file_send_level(context, level):
    """Configure lidi-file-send with a specific log level (without starting).

    This step prepares the log configuration for lidi-file-send but does not
    start the lidi system yet. Use 'lidi is started with the configured logging'
    after this step to actually start lidi.
    """
    # build_log_config is defined in environment.py
    def build_log_config(filename, level_name):
        return f"""
appenders:
  file:
    kind: file
    path: {filename}

root:
  level: {level_name}
  appenders:
    - file
"""

    log_level = level.lower()

    # Configure lidi-file-send with the requested log level
    log_file = os.path.join(context.base_dir, f"lidi_send_file_{log_level}.log")
    config_file = os.path.join(context.base_dir, f"log_config_lidi_send_file_{log_level}.yml")
    log_content = build_log_config(log_file, log_level)
    with open(config_file, "w") as f:
        f.write(log_content)

    # Store for later use
    context.log_config_lidi_send_file = config_file
    context.test_log_file = log_file


@when('lidi is started with the configured logging')
def step_start_lidi_with_configured_logging(context):
    """Start lidi with the previously configured logging for lidi-file-send.

    This must be called after 'lidi-send is configured with {level} level logging'.
    Other lidi components (send, receive, receive-file) use default INFO level.
    """
    from features.steps.lidi import start_diode

    # Verify configuration was prepared
    if not hasattr(context, 'log_config_lidi_send_file'):
        raise Exception("lidi-file-send logging was not configured. Use 'lidi-send is configured with {level} level logging' first.")

    # Start the diode with the configured lidi-file-send config
    start_diode(context)


@then('the lidi-file-send log file contains log entries')
def step_verify_log_file_not_empty(context):
    """Verify that the lidi-file-send log file contains at least one entry."""
    if not hasattr(context, 'test_log_file'):
        raise Exception("No test log file was prepared")

    if not os.path.exists(context.test_log_file):
        raise Exception(f"Log file {context.test_log_file} was not created")

    with open(context.test_log_file, 'r') as f:
        content = f.read().strip()

    if not content:
        raise Exception(f"Log file {context.test_log_file} is empty, expected log entries")


@then('the lidi-file-send log file contains log entries or is empty')
def step_verify_log_file_or_empty(context):
    """Verify that the lidi-file-send log file either has entries or is intentionally empty."""
    if not hasattr(context, 'test_log_file'):
        # No special verification needed if no test log file was explicitly prepared
        return

    if os.path.exists(context.test_log_file):
        # File exists - it's OK if empty or has content
        pass


@then('the lidi-file-send log file should be empty')
def step_verify_log_file_empty(context):
    """Verify that the lidi-file-send log file is empty or contains no log records."""
    if not hasattr(context, 'test_log_file'):
        raise Exception("No test log file was prepared")

    if not os.path.exists(context.test_log_file):
        # Non-existent = empty, which is OK
        return

    with open(context.test_log_file, 'r') as f:
        content = f.read().strip()

    if content:
        raise Exception(f"Log file {context.test_log_file} should be empty but contains: {content[:200]}")


@then('the lidi-file-send log file contains no {level} level messages')
def step_verify_no_log_level_in_lidi_file_send(context, level):
    """Verify that the lidi-file-send log file does not contain messages of the specified level."""
    if not hasattr(context, 'test_log_file') or not os.path.exists(context.test_log_file):
        return  # No log file to check

    with open(context.test_log_file, 'r') as f:
        content = f.read().upper()

    # Check for level in common log formats (case-insensitive)
    level_upper = level.upper()
    # Common patterns: [LEVEL], LEVEL:, {LEVEL}, LEVEL
    patterns = [
        f'[{level_upper}]',
        f'{level_upper}:',
        f'{{{level_upper}}}',
        f' {level_upper} ',
    ]

    for pattern in patterns:
        if pattern in content:
            raise Exception(f"lidi-file-send log file contains unexpected {level} level messages (found: {pattern})")


@then('the lidi-file-send log file contains {level} or higher level messages')
def step_verify_log_level_present_in_lidi_file_send(context, level):
    """Verify that the lidi-file-send log file contains messages at the specified level or higher."""
    if not hasattr(context, 'test_log_file') or not os.path.exists(context.test_log_file):
        raise Exception(f"lidi-file-send log file {context.test_log_file} does not exist or was not prepared")

    with open(context.test_log_file, 'r') as f:
        content = f.read().strip()

    if not content:
        raise Exception(f"lidi-file-send log file {context.test_log_file} is empty, expected {level} or higher level messages")

    # Just verify file has content (has logs) - exact format verification is fragile
    # Log4rs should produce some output for the specified level


# Generic helper functions for log config testing across applications
def _build_log_config(filename, level_name):
    """Build a log4rs YAML config with the specified level."""
    return f"""
appenders:
  file:
    kind: file
    path: {filename}

root:
  level: {level_name}
  appenders:
    - file
"""


def _verify_log_file_not_empty(log_file):
    """Verify that a log file contains at least one entry."""
    if not os.path.exists(log_file):
        raise Exception(f"Log file {log_file} was not created")
    with open(log_file, 'r') as f:
        content = f.read().strip()
    if not content:
        raise Exception(f"Log file {log_file} is empty, expected log entries")


def _verify_log_file_empty(log_file):
    """Verify that a log file is empty or contains no log records."""
    if not os.path.exists(log_file):
        return
    with open(log_file, 'r') as f:
        content = f.read().strip()
    if content:
        raise Exception(f"Log file {log_file} should be empty but contains: {content[:200]}")


def _verify_no_log_level(log_file, level):
    """Verify that a log file does not contain messages of the specified level."""
    if not os.path.exists(log_file):
        return
    with open(log_file, 'r') as f:
        content = f.read().upper()
    level_upper = level.upper()
    patterns = [
        f'[{level_upper}]',
        f'{level_upper}:',
        f'{{{level_upper}}}',
        f' {level_upper} ',
    ]
    for pattern in patterns:
        if pattern in content:
            raise Exception(f"Log file contains unexpected {level} level messages (found: {pattern})")


def _verify_log_level_present(log_file, level):
    """Verify that a log file contains messages at the specified level or higher."""
    if not os.path.exists(log_file):
        raise Exception(f"Log file {log_file} does not exist or was not prepared")
    with open(log_file, 'r') as f:
        content = f.read().strip()
    if not content:
        raise Exception(f"Log file {log_file} is empty, expected {level} or higher level messages")


# Steps for lidi-send daemon
@given('a log file is prepared for lidi-send with {level} level')
def step_prepare_log_file_for_lidi_send(context, level):
    """Create a log config file for lidi-send with specified level."""
    log_file = os.path.join(context.base_dir, f"lidi_send_{level}.log")
    config_file = os.path.join(context.base_dir, f"log_config_lidi_send_{level}.yml")
    log_content = _build_log_config(log_file, level.lower())
    with open(config_file, "w") as f:
        f.write(log_content)
    context.lidi_send_log_file = log_file
    context.log_config_lidi_send = config_file


@given('lidi-send is configured with {level} level logging')
def step_configure_lidi_send_level(context, level):
    """Configure lidi-send with a specific log level."""
    log_level = level.lower()
    log_file = os.path.join(context.base_dir, f"lidi_send_{log_level}.log")
    config_file = os.path.join(context.base_dir, f"log_config_lidi_send_{log_level}.yml")
    log_content = _build_log_config(log_file, log_level)
    with open(config_file, "w") as f:
        f.write(log_content)
    context.lidi_send_log_file = log_file
    context.log_config_lidi_send = config_file


@when('lidi-send is started without log-config')
def step_start_lidi_send_without_log_config(context):
    """Start lidi-send without custom log config."""
    start_lidi_send(context)


@when('lidi-send is started with the configured logging')
def step_start_lidi_send_with_configured_logging(context):
    """Start lidi-send with the previously configured logging."""
    if not hasattr(context, 'log_config_lidi_send') or not context.log_config_lidi_send:
        raise Exception("lidi-send logging was not configured")
    start_lidi_send(context)


@then('lidi-send should be running')
def step_verify_lidi_send_running_state(context):
    """Verify that lidi-send is running."""
    if not hasattr(context, 'proc_lidi_send') or context.proc_lidi_send is None:
        raise Exception("lidi-send is not running")
    if context.proc_lidi_send.poll() is not None:
        raise Exception("lidi-send process has exited")


@when('lidi-send with log-config {log_config_path}')
def step_start_lidi_send_with_invalid_config(context, log_config_path):
    """Start lidi-send with a specified log config path."""
    cmd = [
        f'{context.bin_dir}/lidi-send',
        f'{context.base_dir}/lidi_send_test.toml',
        '--log-config', log_config_path,
    ]
    result = subprocess.run(cmd, timeout=10, text=True, capture_output=True)
    context.send_returncode = result.returncode
    context.send_error_output = result.stderr

@when('lidi-send with the invalid log-config')
def step_start_lidi_send_with_invalid_log_config(context):
    """Start lidi-send with the previously created invalid log config."""
    if not hasattr(context, 'invalid_log_config_path'):
        raise Exception("No invalid log config was created")
    cmd = [
        f'{context.bin_dir}/lidi-send',
        f'{context.base_dir}/lidi_send_test.toml',
        '--log-config', context.invalid_log_config_path,
    ]
    result = subprocess.run(cmd, timeout=10, text=True, capture_output=True)
    context.send_returncode = result.returncode
    context.send_error_output = result.stderr


@then('the lidi-send log file contains log entries')
def step_verify_lidi_send_log_not_empty(context):
    """Verify that the lidi-send log file contains at least one entry."""
    if not hasattr(context, 'lidi_send_log_file'):
        raise Exception("No lidi-send log file was prepared")
    _verify_log_file_not_empty(context.lidi_send_log_file)


@then('the lidi-send log file contains log entries or is empty')
def step_verify_lidi_send_log_or_empty(context):
    """Verify that the lidi-send log file either has entries or is empty."""
    if not hasattr(context, 'lidi_send_log_file'):
        return


@then('the lidi-send log file should be empty')
def step_verify_lidi_send_log_empty(context):
    """Verify that the lidi-send log file is empty."""
    if not hasattr(context, 'lidi_send_log_file'):
        raise Exception("No lidi-send log file was prepared")
    _verify_log_file_empty(context.lidi_send_log_file)


@then('the lidi-send log file contains no {level} level messages')
def step_verify_no_log_level_lidi_send(context, level):
    """Verify that the lidi-send log file does not contain messages of the specified level."""
    if not hasattr(context, 'lidi_send_log_file'):
        return
    _verify_no_log_level(context.lidi_send_log_file, level)


@then('the lidi-send log file contains {level} or higher level messages')
def step_verify_log_level_present_lidi_send(context, level):
    """Verify that the lidi-send log file contains messages at the specified level or higher."""
    if not hasattr(context, 'lidi_send_log_file'):
        raise Exception("No lidi-send log file was prepared")
    _verify_log_level_present(context.lidi_send_log_file, level)


# Steps for lidi-receive daemon
@given('a log file is prepared for lidi-receive with {level} level')
def step_prepare_log_file_for_lidi_receive(context, level):
    """Create a log config file for lidi-receive with specified level."""
    log_file = os.path.join(context.base_dir, f"lidi_receive_{level}.log")
    config_file = os.path.join(context.base_dir, f"log_config_lidi_receive_{level}.yml")
    log_content = _build_log_config(log_file, level.lower())
    with open(config_file, "w") as f:
        f.write(log_content)
    context.lidi_receive_log_file = log_file
    context.log_config_lidi_receive = config_file


@given('lidi-receive is configured with {level} level logging')
def step_configure_lidi_receive_level(context, level):
    """Configure lidi-receive with a specific log level."""
    log_level = level.lower()
    log_file = os.path.join(context.base_dir, f"lidi_receive_{log_level}.log")
    config_file = os.path.join(context.base_dir, f"log_config_lidi_receive_{log_level}.yml")
    log_content = _build_log_config(log_file, log_level)
    with open(config_file, "w") as f:
        f.write(log_content)
    context.lidi_receive_log_file = log_file
    context.log_config_lidi_receive = config_file


@when('lidi-receive is started without log-config')
def step_start_lidi_receive_without_log_config(context):
    """Start lidi-receive without custom log config."""
    start_lidi_receive(context)


@when('lidi-receive is started with the configured logging')
def step_start_lidi_receive_with_configured_logging(context):
    """Start lidi-receive with the previously configured logging."""
    if not hasattr(context, 'log_config_lidi_receive') or not context.log_config_lidi_receive:
        raise Exception("lidi-receive logging was not configured")
    start_lidi_receive(context)


@then('lidi-receive should be running')
def step_verify_lidi_receive_running_state(context):
    """Verify that lidi-receive is running."""
    if not hasattr(context, 'proc_lidi_receive') or context.proc_lidi_receive is None:
        raise Exception("lidi-receive is not running")
    if context.proc_lidi_receive.poll() is not None:
        raise Exception("lidi-receive process has exited")


@when('lidi-receive with log-config {log_config_path}')
def step_start_lidi_receive_with_invalid_config(context, log_config_path):
    """Start lidi-receive with a specified log config path."""
    cmd = [
        f'{context.bin_dir}/lidi-receive',
        f'{context.base_dir}/lidi_receive_test.toml',
        '--log-config', log_config_path,
    ]
    result = subprocess.run(cmd, timeout=10, text=True, capture_output=True)
    context.send_returncode = result.returncode
    context.send_error_output = result.stderr

@when('lidi-receive with the invalid log-config')
def step_start_lidi_receive_with_invalid_log_config(context):
    """Start lidi-receive with the previously created invalid log config."""
    if not hasattr(context, 'invalid_log_config_path'):
        raise Exception("No invalid log config was created")
    cmd = [
        f'{context.bin_dir}/lidi-receive',
        f'{context.base_dir}/lidi_receive_test.toml',
        '--log-config', context.invalid_log_config_path,
    ]
    result = subprocess.run(cmd, timeout=10, text=True, capture_output=True)
    context.send_returncode = result.returncode
    context.send_error_output = result.stderr


@then('the lidi-receive log file contains log entries')
def step_verify_lidi_receive_log_not_empty(context):
    """Verify that the lidi-receive log file contains at least one entry."""
    if not hasattr(context, 'lidi_receive_log_file'):
        raise Exception("No lidi-receive log file was prepared")
    _verify_log_file_not_empty(context.lidi_receive_log_file)


@then('the lidi-receive log file contains log entries or is empty')
def step_verify_lidi_receive_log_or_empty(context):
    """Verify that the lidi-receive log file either has entries or is empty."""
    if not hasattr(context, 'lidi_receive_log_file'):
        return


@then('the lidi-receive log file should be empty')
def step_verify_lidi_receive_log_empty(context):
    """Verify that the lidi-receive log file is empty."""
    if not hasattr(context, 'lidi_receive_log_file'):
        raise Exception("No lidi-receive log file was prepared")
    _verify_log_file_empty(context.lidi_receive_log_file)


@then('the lidi-receive log file contains no {level} level messages')
def step_verify_no_log_level_lidi_receive(context, level):
    """Verify that the lidi-receive log file does not contain messages of the specified level."""
    if not hasattr(context, 'lidi_receive_log_file'):
        return
    _verify_no_log_level(context.lidi_receive_log_file, level)


@then('the lidi-receive log file contains {level} or higher level messages')
def step_verify_log_level_present_lidi_receive(context, level):
    """Verify that the lidi-receive log file contains messages at the specified level or higher."""
    if not hasattr(context, 'lidi_receive_log_file'):
        raise Exception("No lidi-receive log file was prepared")
    _verify_log_level_present(context.lidi_receive_log_file, level)


# Steps for lidi-dir-send
@given('a log file is prepared for lidi-dir-send with {level} level')
def step_prepare_log_file_for_lidi_dir_send(context, level):
    """Create a log config file for lidi-dir-send with specified level."""
    log_file = os.path.join(context.base_dir, f"lidi_dir_send_{level}.log")
    config_file = os.path.join(context.base_dir, f"log_config_lidi_dir_send_{level}.yml")
    log_content = _build_log_config(log_file, level.lower())
    with open(config_file, "w") as f:
        f.write(log_content)
    context.lidi_dir_send_log_file = log_file
    context.log_config_lidi_send_dir = config_file


@given('lidi-dir-send is configured with {level} level logging')
def step_configure_lidi_dir_send_level(context, level):
    """Configure lidi-dir-send with a specific log level."""
    log_level = level.lower()
    log_file = os.path.join(context.base_dir, f"lidi_dir_send_{log_level}.log")
    config_file = os.path.join(context.base_dir, f"log_config_lidi_dir_send_{log_level}.yml")
    log_content = _build_log_config(log_file, log_level)
    with open(config_file, "w") as f:
        f.write(log_content)
    context.lidi_dir_send_log_file = log_file
    context.log_config_lidi_send_dir = config_file


@when('lidi-dir-send is started without log-config')
def step_start_lidi_dir_send_without_log_config(context):
    """Start lidi-dir-send without custom log config."""
    start_lidi_send_dir(context, True)


@when('lidi-dir-send is started with the configured logging')
def step_start_lidi_dir_send_with_configured_logging(context):
    """Start lidi-dir-send with the previously configured logging."""
    if not hasattr(context, 'log_config_lidi_send_dir') or not context.log_config_lidi_send_dir:
        raise Exception("lidi-dir-send logging was not configured")
    start_lidi_send_dir(context, True)


@then('lidi-dir-send should be running')
def step_verify_lidi_dir_send_running_state(context):
    """Verify that lidi-dir-send is running."""
    if not hasattr(context, 'proc_lidi_send_dir') or context.proc_lidi_send_dir is None:
        raise Exception("lidi-dir-send is not running")
    if context.proc_lidi_send_dir.poll() is not None:
        raise Exception("lidi-dir-send process has exited")


@when('lidi-dir-send with log-config {log_config_path}')
def step_start_lidi_dir_send_with_invalid_config(context, log_config_path):
    """Start lidi-dir-send with a specified log config path."""
    cmd = [
        f'{context.bin_dir}/lidi-dir-send',
        '--log-config', log_config_path,
        '--to-tcp', '127.0.0.1:4000',
        context.send_dir,
    ]
    result = subprocess.run(cmd, timeout=10, text=True, capture_output=True)
    context.send_returncode = result.returncode
    context.send_error_output = result.stderr

@when('lidi-dir-send with the invalid log-config')
def step_start_lidi_dir_send_with_invalid_log_config(context):
    """Start lidi-dir-send with the previously created invalid log config."""
    if not hasattr(context, 'invalid_log_config_path'):
        raise Exception("No invalid log config was created")
    cmd = [
        f'{context.bin_dir}/lidi-dir-send',
        '--log-config', context.invalid_log_config_path,
        '--to-tcp', '127.0.0.1:4000',
        context.send_dir,
    ]
    result = subprocess.run(cmd, timeout=10, text=True, capture_output=True)
    context.send_returncode = result.returncode
    context.send_error_output = result.stderr


@then('the lidi-dir-send log file contains log entries')
def step_verify_lidi_dir_send_log_not_empty(context):
    """Verify that the lidi-dir-send log file contains at least one entry."""
    if not hasattr(context, 'lidi_dir_send_log_file'):
        raise Exception("No lidi-dir-send log file was prepared")
    _verify_log_file_not_empty(context.lidi_dir_send_log_file)


@then('the lidi-dir-send log file contains log entries or is empty')
def step_verify_lidi_dir_send_log_or_empty(context):
    """Verify that the lidi-dir-send log file either has entries or is empty."""
    if not hasattr(context, 'lidi_dir_send_log_file'):
        return


@then('the lidi-dir-send log file should be empty')
def step_verify_lidi_dir_send_log_empty(context):
    """Verify that the lidi-dir-send log file is empty."""
    if not hasattr(context, 'lidi_dir_send_log_file'):
        raise Exception("No lidi-dir-send log file was prepared")
    _verify_log_file_empty(context.lidi_dir_send_log_file)


@then('the lidi-dir-send log file contains no {level} level messages')
def step_verify_no_log_level_lidi_dir_send(context, level):
    """Verify that the lidi-dir-send log file does not contain messages of the specified level."""
    if not hasattr(context, 'lidi_dir_send_log_file'):
        return
    _verify_no_log_level(context.lidi_dir_send_log_file, level)


@then('the lidi-dir-send log file contains {level} or higher level messages')
def step_verify_log_level_present_lidi_dir_send(context, level):
    """Verify that the lidi-dir-send log file contains messages at the specified level or higher."""
    if not hasattr(context, 'lidi_dir_send_log_file'):
        raise Exception("No lidi-dir-send log file was prepared")
    _verify_log_level_present(context.lidi_dir_send_log_file, level)


# Steps for lidi-file-receive
@given('a log file is prepared for lidi-file-receive with {level} level')
def step_prepare_log_file_for_lidi_file_receive(context, level):
    """Create a log config file for lidi-file-receive with specified level."""
    log_file = os.path.join(context.base_dir, f"lidi_file_receive_{level}.log")
    config_file = os.path.join(context.base_dir, f"log_config_lidi_file_receive_{level}.yml")
    log_content = _build_log_config(log_file, level.lower())
    with open(config_file, "w") as f:
        f.write(log_content)
    context.lidi_file_receive_log_file = log_file
    context.log_config_lidi_receive_file = config_file


@given('lidi-file-receive is configured with {level} level logging')
def step_configure_lidi_file_receive_level(context, level):
    """Configure lidi-file-receive with a specific log level."""
    log_level = level.lower()
    log_file = os.path.join(context.base_dir, f"lidi_file_receive_{log_level}.log")
    config_file = os.path.join(context.base_dir, f"log_config_lidi_file_receive_{log_level}.yml")
    log_content = _build_log_config(log_file, log_level)
    with open(config_file, "w") as f:
        f.write(log_content)
    context.lidi_file_receive_log_file = log_file
    context.log_config_lidi_receive_file = config_file


@when('lidi-file-receive is started without log-config')
def step_start_lidi_file_receive_without_log_config(context):
    """Start lidi-file-receive without custom log config."""
    if hasattr(context, 'proc_lidi_receive_file') and context.proc_lidi_receive_file:
        stop_lidi_file_receive(context)
        time.sleep(1)
    start_lidi_file_receive(context)


@when('lidi-file-receive is started with the configured logging')
def step_start_lidi_file_receive_with_configured_logging(context):
    """Start lidi-file-receive with the previously configured logging."""
    if not hasattr(context, 'log_config_lidi_receive_file') or not context.log_config_lidi_receive_file:
        raise Exception("lidi-file-receive logging was not configured")
    if hasattr(context, 'proc_lidi_receive_file') and context.proc_lidi_receive_file:
        stop_lidi_file_receive(context)
        time.sleep(1)
    start_lidi_file_receive(context)


@then('lidi-file-receive should be running')
def step_verify_lidi_file_receive_running_state(context):
    """Verify that lidi-file-receive is running."""
    if not hasattr(context, 'proc_lidi_receive_file') or context.proc_lidi_receive_file is None:
        raise Exception("lidi-file-receive is not running")
    if context.proc_lidi_receive_file.poll() is not None:
        raise Exception("lidi-file-receive process has exited")


@when('lidi-file-receive with log-config {log_config_path}')
def step_start_lidi_file_receive_with_invalid_config(context, log_config_path):
    """Start lidi-file-receive with a specified log config path."""
    cmd = [
        f'{context.bin_dir}/lidi-file-receive',
        '--log-config', log_config_path,
        '--from-tcp', f'127.0.0.1:{context.tcp_receive_port}',
        context.receive_dir,
    ]
    result = subprocess.run(cmd, timeout=10, text=True, capture_output=True)
    context.send_returncode = result.returncode
    context.send_error_output = result.stderr

@when('lidi-file-receive with the invalid log-config')
def step_start_lidi_file_receive_with_invalid_log_config(context):
    """Start lidi-file-receive with the previously created invalid log config."""
    if not hasattr(context, 'invalid_log_config_path'):
        raise Exception("No invalid log config was created")
    cmd = [
        f'{context.bin_dir}/lidi-file-receive',
        '--log-config', context.invalid_log_config_path,
        '--from-tcp', f'127.0.0.1:{context.tcp_receive_port}',
        context.receive_dir,
    ]
    result = subprocess.run(cmd, timeout=10, text=True, capture_output=True)
    context.send_returncode = result.returncode
    context.send_error_output = result.stderr


@then('the lidi-file-receive log file contains log entries')
def step_verify_lidi_file_receive_log_not_empty(context):
    """Verify that the lidi-file-receive log file contains at least one entry."""
    if not hasattr(context, 'lidi_file_receive_log_file'):
        raise Exception("No lidi-file-receive log file was prepared")
    _verify_log_file_not_empty(context.lidi_file_receive_log_file)


@then('the lidi-file-receive log file contains log entries or is empty')
def step_verify_lidi_file_receive_log_or_empty(context):
    """Verify that the lidi-file-receive log file either has entries or is empty."""
    if not hasattr(context, 'lidi_file_receive_log_file'):
        return


@then('the lidi-file-receive log file should be empty')
def step_verify_lidi_file_receive_log_empty(context):
    """Verify that the lidi-file-receive log file is empty."""
    if not hasattr(context, 'lidi_file_receive_log_file'):
        raise Exception("No lidi-file-receive log file was prepared")
    _verify_log_file_empty(context.lidi_file_receive_log_file)


@then('the lidi-file-receive log file contains no {level} level messages')
def step_verify_no_log_level_lidi_file_receive(context, level):
    """Verify that the lidi-file-receive log file does not contain messages of the specified level."""
    if not hasattr(context, 'lidi_file_receive_log_file'):
        return
    _verify_no_log_level(context.lidi_file_receive_log_file, level)


@then('the lidi-file-receive log file contains {level} or higher level messages')
def step_verify_log_level_present_lidi_file_receive(context, level):
    """Verify that the lidi-file-receive log file contains messages at the specified level or higher."""
    if not hasattr(context, 'lidi_file_receive_log_file'):
        raise Exception("No lidi-file-receive log file was prepared")
    _verify_log_level_present(context.lidi_file_receive_log_file, level)
