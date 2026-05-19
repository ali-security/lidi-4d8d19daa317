from contextlib import contextmanager
import os

def build_lidi_config(context, udp_port, log_config, side='both'):
    """Build LIDI configuration string based on context and parameters.

    side: 'send', 'receive', or 'both' - which heartbeat value to use
    """
    # Use values from tcp.config.toml example as base
    mtu = getattr(context, 'mtu', 1500) or 1500
    ports = [int(udp_port)]
    block = getattr(context, 'block_size', 20_000) or 20_000
    _repair = getattr(context, 'repair', None)
    repair = _repair if _repair is not None else 1
    max_clients = 2
    hash_val = False
    flush = getattr(context, 'tcp_flush', False)

    # Determine heartbeat value based on side
    if hasattr(context, 'heartbeat_send') and hasattr(context, 'heartbeat_receive'):
        if side == 'send':
            heartbeat = context.heartbeat_send
        elif side == 'receive':
            heartbeat = context.heartbeat_receive
        else:  # 'both' - use send heartbeat for global config
            heartbeat = context.heartbeat_send
    else:
        heartbeat = getattr(context, 'heartbeat', 10)

    # Timeout configuration
    reset_timeout = getattr(context, 'reset_timeout', 2)
    abort_timeout = getattr(context, 'abort_timeout', 60)
    queue_size = getattr(context, 'queue_size', 4096)

    # Build receive section dynamically to handle optional abort_timeout
    udp_receive_mode = getattr(context, 'udp_receive_mode', 'mmsg')
    receive_lines = [
        'log = "INFO"',
        'from = "127.0.0.1"',
        f'mode = "{udp_receive_mode}"',
        f"queue_size = {queue_size}",
        f"reset_timeout = {reset_timeout}",
    ]
    # Only include abort_timeout if it's not disabled (not 0)
    if abort_timeout != 0:
        receive_lines.append(f"abort_timeout = {abort_timeout}")

    receive_lines.extend([
        'prometheus_listen = "127.0.0.1:9002"',
        f"{log_config}",
        f'to = [ "tcp[hash={str(hash_val).lower()},flush={str(flush).lower()}]:127.0.0.1:{context.tcp_receive_port}" ]'
    ])

    # Base configuration similar to tcp.config.toml
    udp_send_mode = getattr(context, 'udp_send_mode', 'mmsg')
    config_lines = [
        f"mtu = {mtu}",
        f"ports = {ports}",
        f"block = {block}",
        f"repair = {repair}",
        f"max_clients = {max_clients}",
        f"heartbeat = {heartbeat}",
        "",
        "[send]",
        'log = "INFO"',
        'to = "127.0.0.1"',
        'to_bind = "0.0.0.0:0"',
        f'mode = "{udp_send_mode}"',
        'prometheus_listen = "127.0.0.1:9001"',
        f"{log_config}",
        f'from = [ "tcp[hash={str(hash_val).lower()},flush={str(flush).lower()}]:127.0.0.1:{context.tcp_send_port}" ]',
        "",
        "[receive]",
    ]
    config_lines.extend(receive_lines)

    return "\n".join(config_lines)

def write_lidi_config(context, filename, udp_port, log_config, side='both'):
    """Write LIDI configuration to file."""
    full_path = os.path.join(context.base_dir, filename)
    log_config_str = f"log4rs_config = \"{log_config}\""
    config_str = build_lidi_config(context, udp_port, log_config_str, side=side)
    with open(full_path, "w") as config_file:
        config_file.write(config_str)
    return full_path

def build_lidi_send_command(context):
    # For send side, use heartbeat_send if available
    original_heartbeat = getattr(context, 'heartbeat', None)
    if hasattr(context, 'heartbeat_send'):
        context.heartbeat = context.heartbeat_send

    lidi_config = write_lidi_config(context, "lidi_send.toml", "5000", context.log_config_lidi_send, side='send')

    # Always restore original (even if it was None)
    if hasattr(context, 'heartbeat_send'):
        if original_heartbeat is not None:
            context.heartbeat = original_heartbeat
        else:
            delattr(context, 'heartbeat')

    lidi_send_command = [f'{context.bin_dir}/lidi-send', lidi_config]

    return lidi_send_command

def build_lidi_receive_command(context):
    # For receive side, use heartbeat_receive if available
    original_heartbeat = getattr(context, 'heartbeat', None)
    if hasattr(context, 'heartbeat_receive'):
        context.heartbeat = context.heartbeat_receive

    # Determine UDP port based on network behavior
    has_network_simulator = (
        context.network_down_after or
        context.network_up_after or
        context.network_drop or
        context.network_max_bandwidth or
        context.bandwidth_must_not_exceed or
        getattr(context, 'network_down_after_duration', None) or
        getattr(context, 'network_blackout_duration', None)
    )
    receiver_bind_udp_port = "6000" if has_network_simulator else "5000"

    lidi_config = write_lidi_config(context, "lidi_receive.toml", receiver_bind_udp_port, context.log_config_lidi_receive, side='receive')

    # Always restore original (even if it was None)
    if hasattr(context, 'heartbeat_receive'):
        if original_heartbeat is not None:
            context.heartbeat = original_heartbeat
        else:
            delattr(context, 'heartbeat')

    lidi_receive_command = [f'{context.bin_dir}/lidi-receive', lidi_config]

    return lidi_receive_command

def build_lidi_receive_file_command(context):
    lidi_receive_file_command = [
        f'{context.bin_dir}/lidi-file-receive',
        '--from-tcp',
        f'127.0.0.1:{context.tcp_receive_port}',
        '--log-config', context.log_config_lidi_receive_file,
    ]

    if getattr(context, 'hash_receive', False):
        lidi_receive_file_command.append('--hash')

    lidi_receive_file_command.append(context.receive_dir)

    return lidi_receive_file_command

def build_lidi_send_dir_command(context, watch, ignore):
    lidi_send_dir_command = [
        f'{context.bin_dir}/lidi-dir-send',
        '--to-tcp', f'127.0.0.1:{context.tcp_send_port}',
        '--log-config', context.log_config_lidi_send_dir
    ]

    if watch:
        lidi_send_dir_command += ['--watch']
    
    if ignore is not None:
        lidi_send_dir_command += ['--ignore', ignore]
        
    lidi_send_dir_command += [context.send_dir]
    
    return lidi_send_dir_command

def build_lidi_send_file_command(context, filename):
    # Get buffer size from context or use default
    buffer_size = getattr(context, 'buffer_size', '8192')

    # Build base command
    base_command = [
        f"{context.bin_dir}/lidi-file-send",
        "--buffer-size",
        buffer_size,
        "--to-tcp",
        f"127.0.0.1:{context.tcp_send_port}",
    ]

    # Add log-level if specified
    if hasattr(context, 'log_level') and context.log_level:
        base_command.extend(['--log-level', context.log_level])

    # Add log-config if not disabled
    if not getattr(context, 'skip_log_config', False):
        # Use override value if provided, otherwise use default
        log_config = getattr(context, 'log_config_override', None) or context.log_config_lidi_send_file
        base_command.extend(['--log-config', log_config])

    # Convert filename to list if needed
    if isinstance(filename, list):
        filename_list = filename
    else:
        filename_list = [filename]

    # Merge base command with filenames
    lidi_send_file_command = base_command + filename_list

    return lidi_send_file_command

def build_network_simulator_command(context):
    # Setup network behavior parameters
    network_simulator_command = [
        f'{context.bin_dir}/lidi-network-simulator',
        '--bind-udp', '0.0.0.0:5000',
        '--to-udp', '127.0.0.1:6000',
        '--log-config', context.log_config_network_behavior
    ]

    # Add network behavior options
    network_options = [
        ('network_down_after', '--network-down-after'),
        ('network_up_after', '--network-up-after'),
        ('network_down_after_duration', '--network-down-after-duration'),
        ('network_blackout_duration', '--network-blackout-duration'),
        ('network_drop', '--loss-rate'),
        ('network_max_bandwidth', '--max-bandwidth'),
        ('bandwidth_must_not_exceed', '--abort-on-max-bandwidth')
    ]

    use_network_simulator = False
    for attr_name, option in network_options:
        attr_value = getattr(context, attr_name, None)
        if attr_value:
            network_simulator_command.extend([option, str(attr_value)])
            use_network_simulator = True

    if not use_network_simulator:
        return None
    else:
        return network_simulator_command
