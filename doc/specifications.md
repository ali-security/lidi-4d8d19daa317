# Lidi — Feature Specification

> Project version: 3.0.0  
> Date: 2026-05-07

---

## Table of contents

1. [Unidirectional transport over UDP](#1-unidirectional-transport-over-udp)
2. [RaptorQ encoding and packet-loss tolerance](#2-raptorq-encoding-and-packet-loss-tolerance)
3. [Multi-protocol endpoint support (TCP, TLS, Unix)](#3-multi-protocol-endpoint-support-tcp-tls-unix)
4. [Simultaneous client multiplexing](#4-simultaneous-client-multiplexing)
5. [UDP send/receive modes: native, msg, mmsg](#5-udp-sendreceive-modes-native-msg-mmsg)
6. [Heartbeat (keepalive signal)](#6-heartbeat-keepalive-signal)
7. [TLS encryption](#7-tls-encryption)
8. [Data integrity hashing (XXHash3)](#8-data-integrity-hashing-xxhash3)
9. [Timeout management (reset and abort)](#9-timeout-management-reset-and-abort)
10. [File transfer (lidi-file-send / lidi-file-receive)](#10-file-transfer-lidi-file-send--lidi-file-receive)
11. [Directory watching (lidi-dir-send)](#11-directory-watching-lidi-dir-send)
12. [UDP tunnel (lidi-udp-send / lidi-udp-receive)](#12-udp-tunnel-lidi-udp-send--lidi-udp-receive)
13. [Bandwidth limiting](#13-bandwidth-limiting)
14. [Configuration via TOML file and CLI](#14-configuration-via-toml-file-and-cli)
15. [Prometheus metrics](#15-prometheus-metrics)
16. [Restart recovery (sender/receiver)](#16-restart-recovery-senderreceiver)
17. [Hostname resolution support](#17-hostname-resolution-support)
18. [C bindings (lidi-bindings)](#18-c-bindings-lidi-bindings)

---

## 1. Unidirectional transport over UDP

**Description:** `lidi-send` accepts incoming TCP/TLS/Unix streams, encodes them into RaptorQ blocks, and sends them over one or more UDP ports to `lidi-receive`. Communication is strictly unidirectional: no acknowledgement or return packet is expected.

**Components:** `lidi-send`, `lidi-receive`, `lidi-protocol`

**Key parameters:**
- `ports`: list of UDP ports used (one worker thread per port)
- `to` (send side): IP address or hostname of the receiver
- `from` (receive side): IP address or hostname to bind the UDP listener

**Block format:** `client_id (2B) | block_type (1B) | data_length (4B) | payload`

**Block types:** `Heartbeat`, `Start`, `Data`, `Abort`, `End`

**Byte order:** little-endian throughout.

---

## 2. RaptorQ encoding and packet-loss tolerance

**Description:** Data is split into fixed-size blocks (`block` bytes) and encoded with RaptorQ fountain codes. Additional repair packets (`repair` %) are appended so that a block can be reconstructed even when a fraction of UDP packets is lost in transit.

**Components:** `lidi-protocol` (`RaptorQ` struct), `lidi-send/src/udp.rs`, `lidi-receive/src/decode.rs`

**Key parameters:**
- `block`: block size in bytes (default: 220 000)
- `repair`: repair packet percentage (default: 1 %)
- `mtu`: UDP MTU (default: 1500, max: 9000)

**Constraints:**
- `repair` must be < 100; values ≥ 100 produce `InvalidRepairPercentage`
- `symbol_count` must fit in a `u16`; otherwise `SymbolCountTooLarge`
- At least 2 repair packets (`MIN_NB_REPAIR_PACKETS = 2`) are always added on top of the percentage calculation

**Behaviour:** If the number of packets received for a block reaches `min_nb_packets` (= `symbol_count + 2`), the RaptorQ decoder attempts reconstruction. On failure the block is lost and `lidi_receive_blocks_decode_failed` is incremented.

---

## 3. Multi-protocol endpoint support (TCP, TLS, Unix)

**Description:** Lidi can accept connections and forward data over three socket types: plain TCP, TLS-encrypted TCP, and Unix domain sockets.

**Send side (`lidi-send`):**
- `from = ["tcp:<ip:port>", "tls:<ip:port>", "unix:<path>"]`
- Multiple endpoints may be listed; they are all listened on simultaneously

**Receive side (`lidi-receive`):**
- `to = ["tcp:<ip:port>", "tls:<ip:port>", "unix:<path>"]`

**Per-endpoint options** (inline in the endpoint string):
- `flush=true` — flush the output socket after every write
- `hash=true` — compute and log XXHash3-128 per transfer

**Compilation features:** `from-tcp`, `from-tls`, `from-unix`, `to-tcp`, `to-tls`, `to-unix`

---

## 4. Simultaneous client multiplexing

**Description:** Both `lidi-send` and `lidi-receive` handle multiple clients/transfers concurrently. Each client is assigned a unique `ClientId` (a 16-bit integer, incrementing with wraparound).

**Components:** `lidi-send/src/server.rs`, `lidi-receive/src/dispatch.rs`, `lidi-receive/src/clients.rs`

**Key parameter:** `max_clients` (default: 2)

**Behaviour:**
- `lidi-send` starts `max_clients` server worker threads, each waiting on the bounded `for_server` channel
- `lidi-receive` dispatch worker routes blocks to active clients via a `HashMap<ClientId, Sender<Block>>`
- A `Start` block creates a new per-client channel; `End` or `Abort` closes it

---

## 5. UDP send/receive modes: native, msg, mmsg

**Description:** Three UDP I/O modes are available with increasing throughput efficiency.

| Mode | Syscall | Advantage |
|------|---------|-----------|
| `native` | `send_to()` / `recv_from()` | Standard, most portable |
| `msg` | `sendmsg()` / `recvmsg()` | Control over iovec scatter-gather |
| `mmsg` | `sendmmsg()` / `recvmmsg()` | Batch up to 1024 packets per syscall |

**Parameter:** `mode` (independent for send and receive sides)

**Compilation features:** `send-native`, `send-msg`, `send-mmsg`, `receive-native`, `receive-msg`, `receive-mmsg`

**Behaviour:** If the configured mode was not compiled in, a warning is logged and the first available compiled mode is used instead.

---

## 6. Heartbeat (keepalive signal)

**Description:** `lidi-send` periodically emits `Heartbeat` blocks to signal that the channel is alive. `lidi-receive` monitors their arrival.

**Parameter:** `heartbeat` in seconds (0 = disabled)

**Behaviour:**
- Send side: a dedicated thread sends a `Heartbeat` block every N seconds
- Receive side: if no heartbeat is received within the configured interval, a warning is logged and `lidi_receive_heartbeat_missed` is incremented; the connection is **not** closed
- If the `heartbeat` compilation feature is absent, the parameter is silently ignored with a log warning

**Compilation feature:** `heartbeat`

---

## 7. TLS encryption

**Description:** TCP connections between client applications and `lidi-send`/`lidi-receive` can be encrypted with TLS.

**Components:** `lidi-command-utils/src/tls.rs`

**Configuration parameters** (under `[send.tls]` / `[receive.tls]`):
- `key`: path to the PEM private key file
- `certificate`: path to the PEM certificate file
- `ca`: path to the accepted CA PEM file
- `tls_min`: minimum accepted TLS version (`tls1_1`, `tls1_2`, `tls1_3`)
- `tls_method`: Mozilla security preset (default: `mozilla_modern_v5`)
- `ciphers`: custom TLS cipher list
- `groups`: elliptic-curve groups

**Available presets:** `Mozilla_Intermediate_v4`, `Mozilla_Intermediate_v5`, `Mozilla_Modern_v4`, `Mozilla_Modern_v5` (default)

**Compilation features:** `from-tls`, `to-tls`, `tls` (lidi-clients)

---

## 8. Data integrity hashing (XXHash3)

**Description:** An optional XXHash3-128 hash can be computed and logged per transfer, on both the sender and receiver side, to verify data integrity end-to-end.

**Components:** `lidi-command-utils/src/hash.rs`

**Activation:** Set the `hash=true` option on the endpoint string.  
Example: `tcp[hash=true]:127.0.0.1:4000`

**Behaviour:** The hash is logged at `INFO` level at the end of each transfer:  
`client XXXX: hash is 0x...`

**Compilation feature:** `hash`

---

## 9. Timeout management (reset and abort)

**Description:** `lidi-receive` provides two independent timeout mechanisms.

### reset_timeout
- **Default:** 2 seconds
- **Behaviour:** If no UDP packets arrive for this duration, the internal RaptorQ decoder state is reset (partially received blocks are discarded)
- **Purpose:** Clean recovery after a network interruption

### abort_timeout
- **Default:** disabled (no timeout)
- **Behaviour:** If a client receives no data for this duration, its connection is closed
- **Purpose:** Reclaim resources from stale or disconnected downstream clients

---

## 10. File transfer (lidi-file-send / lidi-file-receive)

**Description:** `lidi-file-send` sends a single file through `lidi-send`; `lidi-file-receive` receives it from `lidi-receive`. A minimal application-level protocol encodes the filename and file size at the start of the transfer.

**Components:** `lidi-clients/src/file/`

**Behaviour:**
- `lidi-file-send` opens a TCP connection to `lidi-send`, transmits metadata (name, size), then the file contents
- `lidi-file-receive` listens on TCP from `lidi-receive`, reads metadata, then writes the file to disk
- Optional integrity check with `--hash`

---

## 11. Directory watching (lidi-dir-send)

**Description:** `lidi-dir-send` watches a directory using inotify and automatically sends newly appearing files via `lidi-send`. Files already present in the directory when the tool starts are also sent.

**Components:** `lidi-clients/` (feature `inotify`)

**Behaviour:**
- Monitors `CLOSE_WRITE` and `MOVED_TO` inotify events (file copy and move)
- Files present at startup are sent before watching for new events
- Exclusion patterns (regex) are supported via `--ignore`
- `--max-files` option limits the number of concurrent file transfers

**Compilation feature:** `inotify`

---

## 12. UDP tunnel (lidi-udp-send / lidi-udp-receive)

**Description:** `lidi-udp-send` and `lidi-udp-receive` allow arbitrary UDP traffic to cross the diode by encapsulating UDP datagrams inside TCP connections to `lidi-send`/`lidi-receive`.

**Components:** `lidi-clients/src/udp/`

---

## 13. Bandwidth limiting

**Description:** UDP throughput can be capped using the Linux `tc` tool (HTB qdisc). For testing purposes, `lidi-network-simulator` can also simulate packet loss and bandwidth constraints.

**Tools:** `tc` (Linux kernel traffic control), `lidi-network-simulator`

**Test parameter:** `max throughput` expressed in Behave scenarios (e.g. `100mbit`, `990kbit`)

---

## 14. Configuration via TOML file and CLI

**Description:** All parameters can be specified in a TOML configuration file and/or as CLI arguments. CLI arguments take precedence over the file.

**Components:** `lidi-command-utils/src/config.rs`

**TOML structure:** Common parameters at the root level; send-specific under `[send]`; receive-specific under `[receive]`; TLS under `[send.tls]` / `[receive.tls]`.

**Parsing:** TOML via `serde` + `toml` crate; CLI via `clap` (compilation feature `command-line`).

**Unknown fields** in TOML are rejected (`deny_unknown_fields`), producing a clear parsing error.

---

## 15. Prometheus metrics

**Description:** Both `lidi-send` and `lidi-receive` can expose Prometheus metrics on a configurable HTTP address.

**Parameter:** `prometheus_listen` (e.g. `127.0.0.1:9001`)

**Sender metrics:** `lidi_send_block_recycler_len` (gauge), `lidi_send_udp_queue_len` (gauge), `lidi_send_udp_packets` (counter), `lidi_error_udp_packets` (counter)

**Receiver metrics:** `lidi_receive_reblock_queue_len`, `lidi_receive_decode_queue_len`, `lidi_receive_dispatch_queue_len` (gauges), `lidi_receive_blocks_reassembled`, `lidi_receive_blocks_lost`, `lidi_receive_blocks_decode_failed`, `lidi_receive_blocks_decoded`, `lidi_receive_heartbeat_missed`, `lidi_receive_client_queue_full`, `lidi_receive_packets_ignored`, `lidi_receive_blocks_for_inactive_client` (counters), `lidi_receive_udp_packets` (counter), `lidi_receive_decode_with_n_packets` (histogram)

**Compilation feature:** `prometheus`

---

## 16. Restart recovery (sender/receiver)

**Description:** Both `lidi-send` and `lidi-receive` can be restarted without permanently disrupting the overall system. Transfers that were not in progress at restart time are unaffected.

**Behaviour:**
- Restarting `lidi-receive`: active downstream connections are lost but the service resumes as soon as `lidi-send` reconnects
- Restarting `lidi-send`: in-progress transfers are aborted (implicit `Abort`), but the service resumes for subsequent transfers
- `lidi-dir-send`: automatically reconnects to `lidi-send` after it restarts

---

## 17. Hostname resolution support

**Description:** The `to` (send) and `from` (receive) parameters accept DNS hostnames in addition to IPv4 addresses. Resolution is performed at startup.

**Constraint:** If a hostname resolves to more than one IPv4 address, an error is returned: `hostname matches several addresses`.

**IPv4 only:** IPv6 addresses are filtered out; lidi only supports IPv4.

---

## 18. C bindings (lidi-bindings)

**Description:** The `lidi-bindings` crate exposes a C-compatible API so that non-Rust applications can integrate lidi file transfer.

**Exported functions:**
- `diode_new_config()` / `diode_free_config()` — allocate and free a configuration object
- `diode_send_file()` — send a file through the diode
- `diode_receive_files()` — receive files from the diode

**Component:** `lidi-bindings/src/lib.rs`
