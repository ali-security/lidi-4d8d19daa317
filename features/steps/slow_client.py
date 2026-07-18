# Slow TCP client simulator for memory stress testing
# Connects to lidi-receive and intentionally reads data slowly
# to trigger unbounded queue growth

import socket
import subprocess
import time
import threading
import os
import ctypes
import logging

log = logging.getLogger(__name__)

# ptrace constants for per-thread pause (replaces SIGSTOP/SIGCONT)
_libc = ctypes.CDLL("libc.so.6", use_errno=True)
_libc.ptrace.restype = ctypes.c_long
_libc.ptrace.argtypes = [ctypes.c_long, ctypes.c_long, ctypes.c_void_p, ctypes.c_void_p]

PTRACE_SEIZE = 0x4206
PTRACE_INTERRUPT = 0x4207
PTRACE_DETACH = 17
PTRACE_SEIZE_DEFAULT_OPTIONS = 0

def _ptrace(request, tid, addr=0, data=0):
    """Thin wrapper around libc ptrace(2). Raises OSError on failure."""
    ctypes.set_errno(0)
    res = _libc.ptrace(request, tid, ctypes.c_void_p(addr), ctypes.c_void_p(data))
    if res == -1:
        errno = ctypes.get_errno()
        if errno != 0:
            raise OSError(errno, os.strerror(errno))
    return res


class SlowTcpClient:
    """TCP client that reads very slowly to simulate stalled client."""

    def __init__(self, host, port, read_rate_kbs=10, max_duration=60):
        """
        Args:
            host: Target host
            port: Target port
            read_rate_kbs: Read rate in KB/s (default 10 KB/s = very slow)
            max_duration: Maximum test duration in seconds
        """
        self.host = host
        self.port = port
        self.read_rate_kbs = read_rate_kbs
        self.max_duration = max_duration
        self.socket = None
        self.bytes_read = 0
        self.thread = None
        self.running = False
        self.error = None

    def connect(self):
        """Connect to server."""
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.socket.connect((self.host, self.port))

    def start_reading(self):
        """Start reading data slowly in background thread."""
        self.running = True
        self.thread = threading.Thread(target=self._read_loop, daemon=True)
        self.thread.start()

    def _read_loop(self):
        """Read data slowly from socket."""
        try:
            chunk_size = self.read_rate_kbs * 1024  # bytes per second
            delay_per_chunk = 1.0  # read chunk every 1 second
            deadline = time.time() + self.max_duration

            while time.time() < deadline and self.running:
                try:
                    # Read chunk_size bytes (or less if available)
                    data = self.socket.recv(chunk_size)
                    if not data:
                        # Connection closed by server
                        break
                    self.bytes_read += len(data)
                    # Artificial delay to achieve desired read rate
                    time.sleep(delay_per_chunk)
                except socket.timeout:
                    continue
                except Exception as e:
                    self.error = str(e)
                    break
        except Exception as e:
            self.error = str(e)

    def stop(self):
        """Stop reading and close socket."""
        self.running = False
        if self.thread:
            self.thread.join(timeout=5)
        if self.socket:
            try:
                self.socket.close()
            except:
                pass

    def get_bytes_read(self):
        """Return total bytes read."""
        return self.bytes_read


def get_process_memory_mb(pid):
    """Get RSS memory usage of a process in MB."""
    try:
        with open(f'/proc/{pid}/status') as f:
            for line in f:
                if line.startswith('VmRSS:'):
                    # VmRSS is in kB
                    kb = int(line.split()[1])
                    return kb / 1024.0
    except:
        return None


def monitor_process_memory(pid, interval=0.5, max_duration=60):
    """Monitor process memory usage over time.

    Returns list of (timestamp, memory_mb) tuples.
    """
    samples = []
    deadline = time.time() + max_duration

    while time.time() < deadline:
        mem = get_process_memory_mb(pid)
        if mem is not None:
            samples.append((time.time(), mem))
        time.sleep(interval)

    return samples


def find_thread_tid(pid, thread_name):
    """Find a thread's Linux TID by its name within a process.

    Thread names are read from /proc/<pid>/task/<tid>/comm.
    Rust threads named with thread::Builder::name() appear there.
    Returns the TID (int) or None if not found.
    """
    task_dir = f'/proc/{pid}/task'
    try:
        tids = os.listdir(task_dir)
    except FileNotFoundError:
        return None
    for tid in tids:
        try:
            with open(f'{task_dir}/{tid}/comm') as f:
                if f.read().strip() == thread_name:
                    return int(tid)
        except (FileNotFoundError, PermissionError):
            continue
    return None


def wait_for_thread(pid, thread_name, timeout=2.0):
    """Poll for a thread's TID until it appears or timeout elapses.

    Some worker threads (e.g. reorder_<N>) are spawned per-client, only once
    a client connection is fully established (TCP handshake + first Start
    block routed through dispatch). Unlike long-lived pipeline threads
    (reblock_<port>, dispatch, client_<N>) which exist from process start,
    these threads may not exist yet right after firing a background transfer.
    Returns the TID (int) or None if the thread never appeared within timeout.
    """
    deadline = time.time() + timeout
    tid = find_thread_tid(pid, thread_name)
    while tid is None and time.time() < deadline:
        time.sleep(0.01)
        tid = find_thread_tid(pid, thread_name)
    return tid


def dump_all_thread_states(pid):
    """Return {thread_name: state} for every thread in the process.

    Used to verify that ptrace affects only the target thread,
    not the whole process.
    """
    task_dir = f'/proc/{pid}/task'
    result = {}
    try:
        tids = os.listdir(task_dir)
    except FileNotFoundError:
        return result
    for tid in tids:
        try:
            with open(f'{task_dir}/{tid}/comm') as f:
                name = f.read().strip()
            with open(f'{task_dir}/{tid}/stat') as f:
                state = f.read().split()[2]
            result[f"{name}({tid})"] = state
        except (FileNotFoundError, PermissionError):
            continue
    return result


def ptrace_stop_thread(pid, tid, timeout=2.0):
    """Stop a single thread via ptrace, without affecting any other thread.

    Uses PTRACE_SEIZE + PTRACE_INTERRUPT to stop the target tid.
    Must be called from the same Python thread that will call ptrace_resume_thread().

    Returns True on success, False if the thread could not be stopped within timeout.
    """
    try:
        _ptrace(PTRACE_SEIZE, tid, 0, PTRACE_SEIZE_DEFAULT_OPTIONS)
        _ptrace(PTRACE_INTERRUPT, tid, 0, 0)
    except OSError as e:
        log.error(f"ptrace SEIZE/INTERRUPT failed: {e}")
        return False

    WUNTRACED = 0x00000002
    __WALL = 0x40000000
    deadline = time.time() + timeout

    while time.time() < deadline:
        try:
            pid_ret, status = os.waitpid(tid, WUNTRACED | __WALL)
            if pid_ret == tid:
                return True
        except ChildProcessError:
            pass

        try:
            with open(f'/proc/{pid}/task/{tid}/stat') as f:
                state = f.read().split()[2]
                if state == 't':
                    return True
        except (FileNotFoundError, PermissionError):
            pass

        time.sleep(0.01)

    return False


def ptrace_resume_thread(tid):
    """Resume and detach a thread stopped with ptrace_stop_thread()."""
    try:
        _ptrace(PTRACE_DETACH, tid, 0, 0)
    except OSError as e:
        if e.errno != 3:
            log.warning(f"ptrace DETACH failed (errno={e.errno}): {e}")
            raise


def starve_thread_via_cpu_pinning(pid, tid, duration_seconds):
    """Pause a SINGLE thread via ptrace (PTRACE_SEIZE/PTRACE_INTERRUPT),
    leaving all other threads in the process running normally.

    NOTE: function name kept for backward compatibility; it no longer uses CPU pinning.
    It uses ptrace to achieve true per-thread pause.

    Blocks the caller for approximately duration_seconds while the target tid is paused.
    """
    def read_thread_stats():
        try:
            with open(f'/proc/{pid}/task/{tid}/stat') as f:
                parts = f.read().split()
                return {'state': parts[2]}
        except Exception:
            return None

    stats_before = read_thread_stats()

    stopped = ptrace_stop_thread(pid, tid, timeout=2.0)

    if stopped:
        mid_states = dump_all_thread_states(pid)
        print(f"\n[DEBUG] All thread states during pause: {mid_states}\n", flush=True)
        log.info(f"All thread states during pause: {mid_states}")

        time.sleep(duration_seconds)

    ptrace_resume_thread(tid)
    time.sleep(0.05)

    stats_after = read_thread_stats()
    if stats_before and stats_after:
        log.info(f"Thread {tid} state: before={stats_before['state']} after={stats_after['state']}")

    if not stopped:
        raise RuntimeError(
            f"ptrace failed to stop thread {tid} within timeout — "
            f"check CAP_SYS_PTRACE / /proc/sys/kernel/yama/ptrace_scope"
        )
