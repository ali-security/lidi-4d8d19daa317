import subprocess
import time
import psutil

PROCESS_READY_DELAY = 1  # seconde
PROCESS_READY_DELAY_EXTENDED = 2  # seconde pour les processus plus lents


def kill_process_safe(process_attr_name, process_name, context):
    """Kill a process with error handling."""
    if hasattr(context, process_attr_name):
        process = getattr(context, process_attr_name)
        if process:
            try:
                if process.poll() is None:
                    process.kill()
                    try:
                        process.wait(timeout=2)
                    except subprocess.TimeoutExpired:
                        print(f"{process_name} did not terminate after SIGKILL")
            except Exception as e:
                print(f"Error closing {process_name}: {e}")


def stop_process(context, process_attr):
    """Stop a process if it exists."""
    if hasattr(context, process_attr):
        process = getattr(context, process_attr)
        if process:
            try:
                process.kill()
            except Exception:
                # Process might have already terminated
                pass


def nice(process_name):
    """Set process priority (niceness) if running as root."""
    import os
    for proc in psutil.process_iter():
        if process_name in proc.name():
            process = psutil.Process(proc.pid)
            # must be root
            if os.getuid() == 0:
                process.nice(-20)
            return
