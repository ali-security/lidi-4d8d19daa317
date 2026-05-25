# Slow TCP client simulator for memory stress testing
# Connects to lidi-receive and intentionally reads data slowly
# to trigger unbounded queue growth

import socket
import subprocess
import time
import threading
import os


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


def starve_thread_via_cpu_pinning(pid, tid, duration_seconds):
    """Starve a specific thread by pinning it to a CPU-saturated core.

    Strategy (no ptrace / no root required):
    1. Pin the target thread to CPU 0 with ``taskset``.
    2. Set it to SCHED_IDLE (lowest priority) with ``chrt``.
    3. Spin a CPU hog on CPU 0 at SCHED_OTHER priority.
    4. With SCHED_IDLE on a fully loaded CPU the thread cannot run.
    5. Other lidi-receive threads run freely on CPUs 1-N.
    6. After duration_seconds kill the hog and restore affinity / scheduling.

    While the target thread is starved, queues that feed it fill up.
    Blocks the caller for approximately duration_seconds.
    """
    # Save original CPU affinity mask (hex string, e.g. "ffff")
    result = subprocess.run(['taskset', '-p', str(tid)], capture_output=True, text=True)
    original_affinity = result.stdout.strip().split()[-1] if result.returncode == 0 else 'ffffffff'

    # Pin target thread to CPU 0 only
    subprocess.run(['taskset', '-p', '0x1', str(tid)], capture_output=True)

    # Drop to SCHED_IDLE — runs only when CPU has zero demand
    subprocess.run(['chrt', '-i', '-p', '0', str(tid)], capture_output=True)

    # Keep CPU 0 at 100 % so the SCHED_IDLE thread never gets scheduled
    hog = subprocess.Popen(
        ['taskset', '-c', '0', 'dd', 'if=/dev/zero', 'of=/dev/null'],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    try:
        time.sleep(duration_seconds)
    finally:
        hog.terminate()
        try:
            hog.wait(timeout=3)
        except subprocess.TimeoutExpired:
            hog.kill()
        # Restore normal scheduling and full CPU affinity
        subprocess.run(['chrt', '-o', '-p', '0', str(tid)], capture_output=True)
        subprocess.run(['taskset', '-p', original_affinity, str(tid)], capture_output=True)
