"""
Memory consumption analyzer for debugging thread starvation tests.
Tracks RSS, queue sizes, and thread activity during pause.
"""

import subprocess
import time
import logging
from typing import Dict, List
import os

log = logging.getLogger(__name__)


class MemorySample:
    """Single memory measurement at a point in time."""
    def __init__(self, timestamp: float, rss_mb: float, vms_mb: float, thread_state: str):
        self.timestamp = timestamp
        self.rss_mb = rss_mb
        self.vms_mb = vms_mb
        self.thread_state = thread_state
        self.elapsed = 0.0

    def __repr__(self):
        return f"MemorySample(t={self.elapsed:.1f}s, RSS={self.rss_mb:.1f}MB, VMS={self.vms_mb:.1f}MB, state={self.thread_state})"


class MemoryAnalyzer:
    """Analyzes memory consumption during thread starvation tests."""

    def __init__(self, pid: int, tid: int = None):
        self.pid = pid
        self.tid = tid
        self.samples: List[MemorySample] = []
        self.start_time = None
        self.prometheus_metrics = {}

    def sample_now(self, label: str = "") -> MemorySample:
        """Take a memory sample right now."""
        if self.start_time is None:
            self.start_time = time.time()

        elapsed = time.time() - self.start_time
        rss_mb, vms_mb = self._get_memory()
        thread_state = self._get_thread_state()

        sample = MemorySample(time.time(), rss_mb, vms_mb, thread_state)
        sample.elapsed = elapsed
        self.samples.append(sample)

        log.debug(f"[{elapsed:.1f}s] {sample} {label}")
        return sample

    def record_prometheus_metric(self, metric_name: str, value: float, label: str = ""):
        """Record a Prometheus metric value."""
        if metric_name not in self.prometheus_metrics:
            self.prometheus_metrics[metric_name] = []

        elapsed = time.time() - self.start_time if self.start_time else 0
        self.prometheus_metrics[metric_name].append({
            'elapsed': elapsed,
            'value': value,
            'label': label
        })
        log.debug(f"[{elapsed:.1f}s] Prometheus {metric_name}={value} {label}")

    def _get_memory(self) -> tuple:
        """Get RSS and VMS in MB from /proc/[pid]/status."""
        try:
            with open(f'/proc/{self.pid}/status') as f:
                rss = vms = 0
                for line in f:
                    if line.startswith('VmRSS:'):
                        rss = int(line.split()[1]) / 1024  # kB -> MB
                    elif line.startswith('VmSize:'):
                        vms = int(line.split()[1]) / 1024  # kB -> MB
                return rss, vms
        except Exception as e:
            log.warning(f"Failed to read /proc memory: {e}")
            return 0, 0

    def _get_thread_state(self) -> str:
        """Get thread state from /proc/[pid]/task/[tid]/stat."""
        if not self.tid:
            return "?"
        try:
            with open(f'/proc/{self.pid}/task/{self.tid}/stat') as f:
                parts = f.read().split()
                return parts[2]  # State: R/S/D/T/etc
        except Exception as e:
            log.warning(f"Failed to read thread state: {e}")
            return "?"

    def generate_report(self) -> str:
        """Generate a detailed analysis report."""
        if not self.samples:
            return "No samples collected"

        report = []
        report.append("\n" + "=" * 80)
        report.append("MEMORY CONSUMPTION ANALYSIS REPORT")
        report.append("=" * 80)

        # Basic stats
        start = self.samples[0]
        end = self.samples[-1]
        report.append(f"\nDuration: {end.elapsed:.1f}s")
        report.append(f"Samples: {len(self.samples)}")

        # Memory growth
        rss_growth = end.rss_mb - start.rss_mb
        vms_growth = end.vms_mb - start.vms_mb
        report.append(f"\nMemory Growth:")
        report.append(f"  RSS: {start.rss_mb:.1f}MB → {end.rss_mb:.1f}MB (Δ{rss_growth:+.1f}MB)")
        report.append(f"  VMS: {start.vms_mb:.1f}MB → {end.vms_mb:.1f}MB (Δ{vms_growth:+.1f}MB)")

        # Peak values
        peak_rss = max(s.rss_mb for s in self.samples)
        peak_vms = max(s.vms_mb for s in self.samples)
        report.append(f"\nPeak Values:")
        report.append(f"  RSS: {peak_rss:.1f}MB")
        report.append(f"  VMS: {peak_vms:.1f}MB")

        # Growth rate (MB/s)
        if end.elapsed > 0:
            rss_rate = rss_growth / end.elapsed
            report.append(f"\nGrowth Rate:")
            report.append(f"  RSS: {rss_rate:.2f} MB/s")

        # Sample timeline
        report.append(f"\nSample Timeline:")
        for sample in self.samples:
            report.append(f"  {sample}")

        # Prometheus metrics
        if self.prometheus_metrics:
            report.append(f"\nPrometheus Metrics:")
            for metric_name, values in self.prometheus_metrics.items():
                if values:
                    start_val = values[0]['value']
                    end_val = values[-1]['value']
                    growth = end_val - start_val
                    report.append(f"  {metric_name}: {start_val:.0f} → {end_val:.0f} (Δ{growth:+.0f})")

        # Thread state analysis
        states = [s.thread_state for s in self.samples]
        if 'R' in states:
            report.append(f"\nWARNING: Thread was RUNNING (R) during pause!")
        if 'D' in states:
            report.append(f"WARNING: Thread was in UNINTERRUPTIBLE SLEEP (D)")
        if all(s == 'S' for s in states):
            report.append(f"\nGOOD: Thread stayed in INTERRUPTIBLE SLEEP (S)")

        report.append("=" * 80 + "\n")
        return "\n".join(report)


def get_prometheus_gauge(context, metric_name: str) -> float:
    """Read a single Prometheus gauge value."""
    import urllib.request
    url = 'http://127.0.0.1:9000/metrics'
    try:
        response = urllib.request.urlopen(url, timeout=2)
        for line in response.read().decode('utf-8').split('\n'):
            if line.startswith(metric_name + ' '):
                return float(line.split()[-1])
    except Exception as e:
        log.warning(f"Failed to read Prometheus metric {metric_name}: {e}")
    return 0.0
