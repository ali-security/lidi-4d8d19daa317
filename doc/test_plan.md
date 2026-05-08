# Lidi — Test Plan per Feature

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

| ID | Description | Preconditions | Steps | Expected result |
|----|-------------|---------------|-------|-----------------|
| T1.1 | Nominal transfer of a small file (10 KB) | lidi-send and lidi-receive running, local network | Send a 10 KB file via lidi-file-send | File received, content identical to source |
| T1.2 | Nominal transfer of a medium file (10 MB) | same | Send a 10 MB file | File received intact |
| T1.3 | Nominal transfer of a large file (100 MB) | same | Send a 100 MB file | File received intact |
| T1.4 | Transport over multiple UDP ports | `ports = [5000, 5001, 5002]` | Send a file | File received; one UDP worker thread per port |
| T1.5 | Block format validation | — | Capture UDP packets (tcpdump) during a transfer | Format `client_id|block_type|data_length|payload` (little-endian) is respected |
| T1.6 | `Abort` block on abrupt client disconnection | — | Start a transfer, then kill the client mid-way | Receiver receives an `Abort` block and closes the channel cleanly |
| T1.7 | `End` block after complete transfer | Nominal transfer | Complete a transfer normally | Receiver receives an `End` block and closes the channel |

---

## 2. RaptorQ encoding and packet-loss tolerance

| ID | Description | Preconditions | Steps | Expected result |
|----|-------------|---------------|-------|-----------------|
| T2.1 | Transfer with no packet loss, repair=1% | Perfect network | Send a 100 KB file | File received intact |
| T2.2 | Transfer with 5% packet loss, repair=5%, small file | lidi-network-simulator drop=5% | Send a 100 KB file | File received intact despite losses |
| T2.3 | Transfer with 5% packet loss, repair=5%, large file | lidi-network-simulator drop=5% | Send a 100 MB file | File received intact |
| T2.4 | High tolerance: 40% drop, repair=40% | lidi-network-simulator drop=40% | Send a 10 MB file | File received intact |
| T2.5 | Capacity exceeded: losses > repair | drop=50%, repair=5% | Send a file | One or more blocks lost; `lidi_receive_blocks_decode_failed` incremented |
| T2.6 | Jumbo MTU 9000 | mtu=9000, jumbo-capable network | Send a 100 MB file | File received; fewer UDP packets used |
| T2.7 | Minimum MTU 1280 | mtu=1280 | Send a 10 MB file | File received despite maximum packet fragmentation |
| T2.8 | Non-default block size | block=1000000 | Send a 10 MB file | File received intact |
| T2.9 | repair=100 (invalid) | repair=100 in config | Start lidi-send | Error: `InvalidRepairPercentage(100)` |
| T2.10 | symbol_count overflow | mtu=1500, block=2000000000 | Start lidi-send | Error: `SymbolCountTooLarge` |

---

## 3. Multi-protocol endpoint support (TCP, TLS, Unix)

| ID | Description | Preconditions | Steps | Expected result |
|----|-------------|---------------|-------|-----------------|
| T3.1 | TCP → TCP transport | features from-tcp, to-tcp | Standard file transfer | File received |
| T3.2 | TLS → TLS transport | Valid certificates, features from-tls, to-tls | Standard file transfer | File received, connection encrypted |
| T3.3 | Unix socket → Unix socket transport | Unix sockets configured | Standard file transfer | File received |
| T3.4 | Multiple simultaneous TCP endpoints (send) | `from = ["tcp:...:4000", "tcp:...:4001"]` | Two clients send concurrently | Both files received |
| T3.5 | `flush=true` endpoint option | `tcp[flush=true]:...` | Send a file | Each block written immediately without buffering |
| T3.6 | `hash=true` endpoint option | `tcp[hash=true]:...`, feature hash | Send a file | XXHash3 logged at end of transfer |
| T3.7 | Missing compiled mode fallback | Binary built without `from-tls`, config requests tls endpoint | Start lidi-send | Warning logged; fallback to available mode |

---

## 4. Simultaneous client multiplexing

| ID | Description | Preconditions | Steps | Expected result |
|----|-------------|---------------|-------|-----------------|
| T4.1 | 10 files of 1 KB sent simultaneously | max_clients=10 | Send 10 files concurrently | All 10 files received |
| T4.2 | 10 files of 10 KB sent simultaneously | max_clients=10 | Send 10 files concurrently | All 10 files received |
| T4.3 | 10 files of 100 KB sent simultaneously | max_clients=10 | Send 10 files concurrently | All 10 files received |
| T4.4 | 10 files of 100 MB sent simultaneously | max_clients=10 | Send 10 files concurrently | All 10 files received |
| T4.5 | ClientId wraparound (> 65535 clients) | — | Send more than 65535 successive transfers | No ClientId collision; wraparound handled correctly |
| T4.6 | max_clients=1 forces serialisation | max_clients=1 | Two clients try to connect simultaneously | Second client waits until first finishes |
| T4.7 | Client connects then disconnects immediately | — | Open a TCP connection and close it immediately | No crash; `Abort` block sent |
| T4.8 | Dispatch routes correctly by ClientId | — | Two files sent in parallel with distinct ClientIds | Each file arrives at its correct destination endpoint |

---

## 5. UDP send/receive modes: native, msg, mmsg

| ID | Description | Preconditions | Steps | Expected result |
|----|-------------|---------------|-------|-----------------|
| T5.1 | Send mode `native` | Binary compiled with `send-native` | Send a 100 MB file, mode=native | File received |
| T5.2 | Send mode `msg` | Binary compiled with `send-msg` | Send a 100 MB file, mode=msg | File received |
| T5.3 | Send mode `mmsg` | Binary compiled with `send-mmsg` | Send a 100 MB file, mode=mmsg | File received |
| T5.4 | Receive mode `native` | Binary compiled with `receive-native` | Receive a 100 MB file, mode=native | File received |
| T5.5 | Receive mode `msg` | Binary compiled with `receive-msg` | Receive a 100 MB file, mode=msg | File received |
| T5.6 | Receive mode `mmsg` | Binary compiled with `receive-mmsg` | Receive a 100 MB file, mode=mmsg | File received |
| T5.7 | Requested mode not compiled — fallback | Binary without `send-mmsg`, config mode=mmsg | Start lidi-send | Warning logged; first available mode used |
| T5.8 | Cross-mode interoperability (send-mmsg + receive-native) | Mixed binaries | Transfer 100 MB | File received correctly |

---

## 6. Heartbeat (keepalive signal)

| ID | Description | Preconditions | Steps | Expected result |
|----|-------------|---------------|-------|-----------------|
| T6.1 | Heartbeat enabled, no missed beats | heartbeat=5 (send), heartbeat=10 (receive) | Start both sides, wait 15 s with no transfer | No heartbeat warning in logs |
| T6.2 | Heartbeat disabled (heartbeat=0) | heartbeat=0 | Start, wait 30 s | No `Heartbeat` blocks sent; no warning |
| T6.3 | Missed heartbeat — warning logged | heartbeat=5 (send), heartbeat=4 (receive) | Stop lidi-send, wait 10 s | `heartbeat missed` log entry on lidi-receive; connection stays open |
| T6.4 | Missed heartbeat — Prometheus counter | feature prometheus enabled | Cut heartbeat source | `lidi_receive_heartbeat_missed` incremented |
| T6.5 | Feature heartbeat not compiled | Binary without feature heartbeat, heartbeat=5 in config | Start | Warning: `heartbeat was not enabled at compilation` |
| T6.6 | Transfer concurrent with active heartbeat | heartbeat=5 | Send a 100 MB file | File received; heartbeats interleaved in the stream without corruption |

---

## 7. TLS encryption

| ID | Description | Preconditions | Steps | Expected result |
|----|-------------|---------------|-------|-----------------|
| T7.1 | Nominal TLS connection | Valid self-signed certificates | Transfer a 10 MB file over TLS | File received; connection encrypted |
| T7.2 | Mutual TLS (mTLS) | Client certificate + CA configured | Transfer with mTLS | File received; bidirectional authentication confirmed |
| T7.3 | Invalid certificate rejected | Different CA on client | TLS client with wrong certificate | Connection refused; TLS error logged |
| T7.4 | Minimum TLS version = 1.3 | tls_min=tls1_3 | Attempt TLS 1.2 connection | Connection refused |
| T7.5 | Mozilla Modern v5 preset (default) | Default config | TLS transfer | Connection established with TLS 1.3 and Mozilla Modern ciphers |
| T7.6 | Custom cipher suite | ciphers="TLS_AES_256_GCM_SHA384" | TLS transfer | File received; only the specified cipher used |
| T7.7 | Feature TLS not compiled | Binary without from-tls | Config with `tls:` endpoint | Error at startup |

---

## 8. Data integrity hashing (XXHash3)

| ID | Description | Preconditions | Steps | Expected result |
|----|-------------|---------------|-------|-----------------|
| T8.1 | Hash enabled, nominal transfer | Endpoint with hash=true, feature hash | Send a file | Hash logged on both sender and receiver; values match |
| T8.2 | Hash disabled | Endpoint without hash option | Send a file | No hash entry in logs |
| T8.3 | Multiple simultaneous transfers with hash | max_clients=3, hash=true | Send 3 files concurrently | Each transfer logs its own individual hash |
| T8.4 | Hash computed per ClientId | hash=true, multiple clients | Two transfers in parallel | Hashes are associated to the correct ClientId in logs |
| T8.5 | Feature hash not compiled | Binary without feature hash, hash=true in endpoint | Start | Compilation error or warning; hash not computed |

---

## 9. Timeout management (reset and abort)

| ID | Description | Preconditions | Steps | Expected result |
|----|-------------|---------------|-------|-----------------|
| T9.1 | reset_timeout triggered after network interruption | reset_timeout=2 | Send packets, cut network for 3 s, resume | After network resumes, receiver accepts new packets normally |
| T9.2 | reset_timeout discards partial blocks | reset_timeout=2 | Interrupt a block mid-way, wait 3 s | Partial block abandoned; subsequent blocks processed correctly |
| T9.3 | abort_timeout closes idle client connection | abort_timeout=5 | Client connected but silent for 6 s | Client connection closed by receiver |
| T9.4 | abort_timeout disabled (default) | No abort_timeout configured | Client silent for 60 s | Connection remains open |
| T9.5 | Transfer resumes after reset | reset_timeout=2 | Interrupt network, resume, send new file | New file received correctly |
| T9.6 | abort_timeout with full queue | queue_size=10, abort_timeout=5 | Slow client, queue fills up | `lidi_receive_client_queue_full` incremented; client closed after timeout |

---

## 10. File transfer (lidi-file-send / lidi-file-receive)

| ID | Description | Preconditions | Steps | Expected result |
|----|-------------|---------------|-------|-----------------|
| T10.1 | Send a 10 KB file | — | lidi-file-send file A of 10 KB | File received; name, size, and content identical |
| T10.2 | Send a 10 MB file | — | lidi-file-send file A of 10 MB | File received intact |
| T10.3 | Send a 100 MB file | — | lidi-file-send file A of 100 MB | File received intact |
| T10.4 | Send 3 sequential files (10 KB each) | — | Send A, B, C sequentially | All 3 files received in order |
| T10.5 | Send 3 sequential 100 MB files | — | Send A, B, C of 100 MB | All 3 files received |
| T10.6 | Transfer with `--hash` option | feature hash | Send file + hash check | Hash logged; integrity confirmed |
| T10.7 | Empty file (0 bytes) | — | Send an empty file | Empty file received; no crash |
| T10.8 | Filename with spaces | — | Send `my file.txt` | File received with correct name |
| T10.9 | lidi-file-receive not started | lidi-file-receive not running | Send a file | lidi-send logs the error; no crash |

---

## 11. Directory watching (lidi-dir-send)

| ID | Description | Preconditions | Steps | Expected result |
|----|-------------|---------------|-------|-----------------|
| T11.1 | Copy a 1 KB file | lidi-dir-send started with --watch | Copy a file into the watched directory | File received on receiver side |
| T11.2 | Move a 1 KB file | same | Move a file into the watched directory | File received on receiver side |
| T11.3 | Copy 3 successive files | same | Copy A, B, C one by one | All 3 files received |
| T11.4 | Move 3 successive files | same | Move A, B, C | All 3 files received |
| T11.5 | Dotfile ignored (copy) | lidi-dir-send with --ignore dotfile pattern | Copy `.A` | `.A` not sent; file remains in source directory |
| T11.6 | Dotfile ignored (move) | same | Move `.A` | `.A` not sent; file remains in source directory |
| T11.7 | File already present before startup | Copy a file BEFORE starting lidi-dir-send | Start lidi-dir-send with --watch | Pre-existing file is sent at startup |
| T11.8 | 500 files pre-existing + 500 added | Copy 500 files before startup | Start, then copy 500 more | All 1000 files received |
| T11.9 | lidi-dir-send resumes after lidi-send restart | lidi-dir-send running | Restart lidi-send, copy a new file | New file received after reconnection |
| T11.10 | Custom regex ignore pattern | --ignore="^\..*$" | Copy `.hidden_file` | File ignored; not sent |

---

## 12. UDP tunnel (lidi-udp-send / lidi-udp-receive)

| ID | Description | Preconditions | Steps | Expected result |
|----|-------------|---------------|-------|-----------------|
| T12.1 | Basic UDP datagram forwarding | lidi-udp-send and lidi-udp-receive running | Send UDP datagrams | Datagrams received on the other side |
| T12.2 | Datagram size preservation | — | Send datagrams of varying sizes | Sizes identical at reception |
| T12.3 | High-throughput UDP | Local network | Send datagrams at high rate | No unexpected packet loss |
| T12.4 | Datagram exceeding MTU | — | Send a datagram larger than UDP MTU | Handled gracefully (fragmented or cleanly refused) |

---

## 13. Bandwidth limiting

| ID | Description | Preconditions | Steps | Expected result |
|----|-------------|---------------|-------|-----------------|
| T13.1 | 100 MB file at 100 Mb/s | tc caps at 100 Mb/s, lidi throughput set to 95 Mb/s | Send a 100 MB file | File received in ~8–9 seconds |
| T13.2 | 3 × 100 MB files at 100 Mb/s | same | Send A, B, C of 100 MB each | All 3 files received without error |
| T13.3 | Bandwidth strictly not exceeded | tc caps at 1 Mb/s, lidi set to 990 Kbit/s | Send a 3 MB file | Bandwidth never exceeds 1 Mb/s (verified with monitoring) |
| T13.4 | 100 MB with MTU 9000 and 100 Mb/s cap | mtu=9000, tc=100 Mb/s | Send a 100 MB file | File received; improved efficiency with jumbo frames |

---

## 14. Configuration via TOML file and CLI

| ID | Description | Preconditions | Steps | Expected result |
|----|-------------|---------------|-------|-----------------|
| T14.1 | Full configuration from TOML file | Valid TOML file | Start lidi-send with the config file | Correct startup |
| T14.2 | Full configuration from CLI | — | Start with all parameters on the command line | Correct startup |
| T14.3 | CLI overrides TOML | TOML with mtu=1500, CLI with --mtu=9000 | Start | mtu=9000 applied (CLI takes precedence) |
| T14.4 | Malformed TOML file | Syntactically invalid TOML | Start with this file | Clear parsing error message |
| T14.5 | Unknown field in TOML | Extra field in TOML | Start | Error: `deny_unknown_fields` |
| T14.6 | Default configuration (no parameters) | No config file, no CLI args | Start | Default values applied (mtu=1500, ports=[5000], block=220000, repair=1, etc.) |
| T14.7 | Multiple endpoints in TOML | `from = ["tcp:...:4000", "tcp:...:4001"]` | Start lidi-send | Two TCP listeners started |
| T14.8 | Hostname in `to` | `to = "myhost.local"` | Start lidi-send | DNS resolved at startup; correct operation |

---

## 15. Prometheus metrics

| ID | Description | Preconditions | Steps | Expected result |
|----|-------------|---------------|-------|-----------------|
| T15.1 | Prometheus endpoint accessible | prometheus_listen=127.0.0.1:9001 | Start, then `curl http://127.0.0.1:9001/metrics` | HTTP 200 response in Prometheus text format |
| T15.2 | Sender UDP packet counter incremented | feature prometheus | Send a file | `lidi_send_udp_packets` > 0 |
| T15.3 | Receiver UDP packet counter incremented | feature prometheus | Receive a file | `lidi_receive_udp_packets` > 0 |
| T15.4 | blocks_decoded counter incremented | feature prometheus | Complete a transfer | `lidi_receive_blocks_decoded` > 0 |
| T15.5 | blocks_lost counter incremented | feature prometheus, losses > repair | Transfer with excessive packet loss | `lidi_receive_blocks_lost` > 0 |
| T15.6 | decode_with_n_packets histogram | feature prometheus | Complete a transfer | Histogram shows distribution of packets per decoded block |
| T15.7 | Prometheus disabled by default | No prometheus_listen configured | Start | No error; no port opened |
| T15.8 | Feature prometheus not compiled | Binary without prometheus, prometheus_listen in config | Start | Warning logged; parameter ignored |

---

## 16. Restart recovery (sender/receiver)

| ID | Description | Preconditions | Steps | Expected result |
|----|-------------|---------------|-------|-----------------|
| T16.1 | Restart lidi-receive: next file received | — | Send A, restart lidi-receive, send B | B received correctly |
| T16.2 | Restart lidi-send: next file received | — | Send A, restart lidi-send, send B | B received correctly |
| T16.3 | Restart lidi-send during transfer: A and C received | — | Send A, start B, restart lidi-send during B, send C | A and C received; B lost (expected) |
| T16.4 | Restart lidi-receive during transfer: A and C received | — | Send A, start B, restart lidi-receive during B, send C | A and C received; B lost (expected) |
| T16.5 | Restart lidi-file-receive: next file received | — | Send A, restart lidi-file-receive, send B | B received correctly |
| T16.6 | lidi-dir-send recovers after lidi-send restart | lidi-dir-send active | Restart lidi-send, copy file B | B received after automatic reconnection |

---

## 17. Hostname resolution support

| ID | Description | Preconditions | Steps | Expected result |
|----|-------------|---------------|-------|-----------------|
| T17.1 | `to = "localhost"` on send side | DNS resolves localhost → 127.0.0.1 | Start lidi-send with to="localhost" | Startup succeeds; UDP sent to 127.0.0.1 |
| T17.2 | `from = "localhost"` on receive side | same | Start lidi-receive with from="localhost" | Startup succeeds |
| T17.3 | Hostname resolving to multiple IPs | DNS resolves "multi.host" → 2 addresses | Configure to="multi.host" | Error: `hostname matches several addresses` |
| T17.4 | Unknown hostname | DNS does not resolve "unknown.host" | Configure to="unknown.host" | Clear DNS resolution error |
| T17.5 | IPv6-only hostname | DNS resolves to IPv6 only | Configure to="ipv6only.host" | Error or filtered out (IPv4-only support) |

---

## 18. C bindings (lidi-bindings)

| ID | Description | Preconditions | Steps | Expected result |
|----|-------------|---------------|-------|-----------------|
| T18.1 | `diode_new_config()` / `diode_free_config()` round-trip | lidi-bindings compiled | Call new then free | No memory leak (verified with valgrind) |
| T18.2 | `diode_send_file()` nominal | lidi-receive running | Send a file via C API | File received on receiver side |
| T18.3 | `diode_receive_files()` nominal | lidi-send running | Receive files via C API | Files written to disk correctly |
| T18.4 | NULL config pointer | — | Call diode_send_file with NULL config | No crash; error code returned |
| T18.5 | Concurrent C API usage | — | Multiple C threads call diode_send_file simultaneously | No race conditions; all files received |
