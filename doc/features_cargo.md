# Cargo Feature Flags — Impact on BDD Tests

This document describes every Rust feature flag in the lidi workspace,
what code it gates, and which BDD test files depend on it.

---

## Feature flags per crate

### lidi-send

| Feature | Gates | Default |
|---------|-------|---------|
| `command-line` | Config file and CLI arg parsing (clap) | yes |
| `from-tcp` | TCP listener endpoint type (`tcp:…` in `[send].from`) | yes |
| `from-tls` | TLS listener endpoint type (`tls:…` in `[send].from`) | yes |
| `from-unix` | Unix socket listener endpoint type (`unix:…` in `[send].from`) | yes |
| `hash` | XXHash3-128 integrity logging per transfer | yes |
| `heartbeat` | Heartbeat packet emission and configuration | yes |
| `log4rs` | File-based structured logging (YAML config) | yes |
| `prometheus` | Metrics HTTP endpoint (`prometheus_listen`) | yes |
| `send-native` | UDP send via `sendto()` (`mode = "native"`) | yes |
| `send-msg` | UDP send via `sendmsg()` (`mode = "msg"`) | yes |
| `send-mmsg` | UDP send via `sendmmsg()` (`mode = "mmsg"`) — **default mode** | yes |

### lidi-receive

| Feature | Gates | Default |
|---------|-------|---------|
| `command-line` | Config file and CLI arg parsing (clap) | yes |
| `to-tcp` | TCP forward endpoint type (`tcp:…` in `[receive].to`) | yes |
| `to-tls` | TLS forward endpoint type (`tls:…` in `[receive].to`) | yes |
| `to-unix` | Unix socket forward endpoint type (`unix:…` in `[receive].to`) | yes |
| `hash` | XXHash3-128 integrity verification per transfer | yes |
| `heartbeat` | Heartbeat timeout detection and logging | yes |
| `log4rs` | File-based structured logging (YAML config) | yes |
| `prometheus` | Metrics HTTP endpoint (`prometheus_listen`) | yes |
| `receive-native` | UDP receive via `recvfrom()` (`mode = "native"`) | yes |
| `receive-msg` | UDP receive via `recvmsg()` (`mode = "msg"`) | yes |
| `receive-mmsg` | UDP receive via `recvmmsg()` (`mode = "mmsg"`) — **default mode** | yes |

### lidi-clients

| Feature | Gates | Default |
|---------|-------|---------|
| `hash` | XXHash3-128 flag in lidi-file-send, lidi-file-receive, lidi-dir-send | yes |
| `inotify` | Directory watch in lidi-dir-send (`--watch`) | yes |
| `log4rs` | File-based structured logging in all client binaries | yes |
| `tcp` | TCP connection mode in all client binaries | yes |
| `tls` | TLS connection mode in all client binaries | yes |
| `unix` | Unix socket connection mode in all client binaries | yes |

### lidi-command-utils (pulled in by lidi-send and lidi-receive)

| Feature | Pulled in by |
|---------|-------------|
| `command-line` | `lidi-send/command-line`, `lidi-receive/command-line` |
| `hash` | `lidi-send/hash`, `lidi-receive/hash` |
| `log4rs` | `lidi-send/log4rs`, `lidi-receive/log4rs` |
| `prometheus` | `lidi-send/prometheus`, `lidi-receive/prometheus` |
| `tls` | `lidi-send/from-tls`, `lidi-receive/to-tls` |

---

## Impact per feature on the BDD test suite

### Universal features — disabling any of these breaks nearly all tests

These features are required by virtually every scenario. Disabling them causes
90–100% of tests to fail at runtime (even though the build may succeed). There
is no practical way to run a useful subset of the test suite without them.

| Feature | Crate | Why it is required by almost every test |
|---------|-------|----------------------------------------|
| `command-line` | lidi-send, lidi-receive | Every test passes a TOML config file as a CLI argument |
| `from-tcp` | lidi-send | All test configs declare a TCP input endpoint for lidi-send |
| `to-tcp` | lidi-receive | All test configs declare a TCP output endpoint for lidi-receive |
| `tcp` | lidi-clients | lidi-file-send and lidi-file-receive connect via TCP |
| `send-mmsg` | lidi-send | Default UDP send mode; test configs use `mode = "mmsg"` |
| `receive-mmsg` | lidi-receive | Default UDP receive mode; test configs use `mode = "mmsg"` |

### Optional features — disabling affects only specific test files

Each `.feature` file documents its requirements in a comment block at the top.

| Feature | Crate(s) | Affected feature files |
|---------|----------|----------------------|
| `hash` | lidi-send, lidi-receive, lidi-clients | `hash.feature` (all 4 scenarios), `file_edge_cases.feature` (1 scenario) |
| `heartbeat` | lidi-send, lidi-receive | `heartbeat.feature` (all 3 scenarios) |
| `log4rs` | lidi-send | `send_log_config.feature` (all 7 scenarios) |
| `log4rs` | lidi-receive | `receive_log_config.feature` (all 7 scenarios) |
| `log4rs` | lidi-clients | `send_file_log_config.feature`, `file_receive_log_config.feature`, `send_dir_log_config.feature` (7 scenarios each) |
| `prometheus` | lidi-send, lidi-receive | `prometheus.feature` (all 14), `stability.feature` (all 11), `memory_receive.feature` (T-SR1/2/4/7), `drop.feature` (1 @wip), `interrupt.feature` (1 scenario) |
| `inotify` | lidi-clients | `send_dir_basics.feature`, `send_dir_ignore.feature`, `send_dir_stability.feature`, `send_dir_log_config.feature` (all in each) |
| `send-native` | lidi-send | `udp_modes.feature` — T5.1 only |
| `send-msg` | lidi-send | `udp_modes.feature` — T5.2 only |
| `receive-native` | lidi-receive | `udp_modes.feature` — T5.4 and T5.8 |
| `receive-msg` | lidi-receive | `udp_modes.feature` — T5.5 only |

### Features with no BDD tests — disabling is safe for the test suite

| Feature | Crate(s) | Notes |
|---------|----------|-------|
| `from-tls` | lidi-send | No TLS test scenarios exist |
| `to-tls` | lidi-receive | No TLS test scenarios exist |
| `tls` | lidi-clients | No TLS test scenarios exist |
| `from-unix` | lidi-send | No Unix socket test scenarios exist |
| `to-unix` | lidi-receive | No Unix socket test scenarios exist |
| `unix` | lidi-clients | No Unix socket test scenarios exist |

---

## Build recipes for reduced feature sets

The table below maps each optional feature to the tests that must be skipped.
Since all features are enabled by default, a plain `just test` always runs
the full suite. These recipes are only relevant for custom builds.

```bash
# ── Without hash ──────────────────────────────────────────────────────────────
cargo build --release --no-default-features \
  --features "command-line,from-tcp,to-tcp,tcp,send-mmsg,receive-mmsg,\
heartbeat,log4rs,prometheus,inotify"
# Skip: hash.feature, and "Send a file with hash enabled" in file_edge_cases.feature

# ── Without prometheus ────────────────────────────────────────────────────────
cargo build --release --no-default-features \
  --features "command-line,from-tcp,to-tcp,tcp,send-mmsg,receive-mmsg,\
hash,heartbeat,log4rs,inotify"
# Skip: prometheus.feature, stability.feature, memory_receive.feature (T-SR1/2/4/7),
#        "Network blackout causes partial blocks…" in interrupt.feature,
#        "@wip Blocks fail to decode…" in drop.feature

# ── Without log4rs ───────────────────────────────────────────────────────────
cargo build --release --no-default-features \
  --features "command-line,from-tcp,to-tcp,tcp,send-mmsg,receive-mmsg,\
hash,heartbeat,prometheus,inotify"
# Skip: send_log_config.feature, receive_log_config.feature,
#        send_file_log_config.feature, file_receive_log_config.feature,
#        send_dir_log_config.feature

# ── Without heartbeat ────────────────────────────────────────────────────────
cargo build --release --no-default-features \
  --features "command-line,from-tcp,to-tcp,tcp,send-mmsg,receive-mmsg,\
hash,log4rs,prometheus,inotify"
# Skip: heartbeat.feature

# ── Without inotify (no lidi-dir-send) ───────────────────────────────────────
cargo build --release --no-default-features \
  --features "command-line,from-tcp,to-tcp,tcp,send-mmsg,receive-mmsg,\
hash,heartbeat,log4rs,prometheus"
# Skip: send_dir_basics.feature, send_dir_ignore.feature,
#        send_dir_stability.feature, send_dir_log_config.feature

# ── Without alternate UDP modes (native, msg) ────────────────────────────────
cargo build --release --no-default-features \
  --features "command-line,from-tcp,to-tcp,tcp,send-mmsg,receive-mmsg,\
hash,heartbeat,log4rs,prometheus,inotify"
# Skip: T5.1 (send-native), T5.2 (send-msg), T5.4 (receive-native),
#        T5.5 (receive-msg), T5.8 (receive-native) in udp_modes.feature

# ── Minimal TCP build (no TLS, no Unix, no hash, no prometheus, no logging) ──
cargo build --release --no-default-features \
  --features "command-line,from-tcp,to-tcp,tcp,send-mmsg,receive-mmsg,heartbeat,inotify"
# Skip: hash.feature, file_edge_cases.feature (hash scenario),
#        prometheus.feature, stability.feature, memory_receive.feature (T-SR1/2/4/7),
#        interrupt.feature (last scenario), drop.feature (@wip),
#        send_log_config.feature, receive_log_config.feature,
#        send_file_log_config.feature, file_receive_log_config.feature,
#        send_dir_log_config.feature
```

---

## Risk summary

| Risk level | Feature disabled | Consequence |
|-----------|-----------------|-------------|
| **Critical** | `command-line`, `from-tcp`, `to-tcp`, `tcp`, `send-mmsg`, `receive-mmsg` | 90–100% of tests fail at runtime |
| **High** | `prometheus` | 30+ scenarios fail across 5 feature files |
| **Medium** | `log4rs` | 35 scenarios fail across 5 log_config feature files |
| **Medium** | `inotify` | 16 scenarios fail across 4 send_dir feature files |
| **Low** | `hash` | 5 scenarios fail across 2 feature files |
| **Low** | `heartbeat` | 3 scenarios fail in heartbeat.feature |
| **Low** | `send-native`, `send-msg`, `receive-native`, `receive-msg` | 1–2 scenarios fail in udp_modes.feature |
| **None** | `from-tls`, `to-tls`, `tls`, `from-unix`, `to-unix`, `unix` | No BDD test impact |
