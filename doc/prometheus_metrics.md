# Prometheus Metrics — Lidi v3.0.0

> Complete reference of Prometheus metrics exposed by lidi-send and lidi-receive.

## Overview

Both `lidi-send` and `lidi-receive` expose Prometheus metrics via HTTP endpoints when compiled with the `prometheus` feature (default).

**Endpoints:**
- `lidi-send`: `http://<listen-address>:9001/metrics` (configurable via `prometheus_listen`)
- `lidi-receive`: `http://<listen-address>:9002/metrics` (configurable via `prometheus_listen`)

**Format:** OpenMetrics text format (Prometheus exposition format v0.0.4)

**Configuration:**
```toml
# Enable Prometheus on non-default port
prometheus_listen = "127.0.0.1:9000"

# Disable Prometheus entirely
prometheus_listen = "disabled"  # or omit the setting
```

---

## Sender Metrics (`lidi-send`)

### Counter: `lidi_send_udp_packets`

**Type:** Counter (monotonically increasing)

**Description:** Total number of UDP packets sent to the receiver since startup.

**Labels:** None

**Units:** Packets

**Example:**
```
lidi_send_udp_packets 32672
```

**Interpretation:**
- Increases each time `lidi-send` sends a UDP packet to the receiver
- One UDP packet per RaptorQ-encoded data or heartbeat block
- Does NOT reset on restart (monotonic counter)

**Usage:**
- Monitor throughput: packets/sec = delta(lidi_send_udp_packets) / time
- Verify data is being sent to the receiver
- Detect sender crashes (counter reset)

---

### Gauge: `lidi_send_udp_queue_len`

**Type:** Gauge (point-in-time value)

**Description:** Current number of UDP packets waiting in the send queue.

**Labels:** None

**Units:** Packets

**Example:**
```
lidi_send_udp_queue_len 1
```

**Interpretation:**
- Snapshot of queue length at metric scrape time
- 0 = queue is empty (ideal)
- > 0 = packets buffered waiting to send (may indicate slow network or receiver congestion)

**Usage:**
- Monitor queue backlog
- Alert if queue grows unbounded (receiver might be down or slow)
- Track application performance impact (high queue = more memory usage)

---

### Gauge: `lidi_send_block_recycler_len`

**Type:** Gauge

**Description:** Current number of recycled/reusable block buffers available in the pool.

**Labels:** None

**Units:** Blocks

**Example:**
```
lidi_send_block_recycler_len 3
```

**Interpretation:**
- Memory optimization: reusable RaptorQ block buffers
- Higher value = more buffer reuse (less allocation)
- Lower value = buffers being held by active transfers
- Should be >= 1 to allow concurrent transfers

**Usage:**
- Monitor memory allocation patterns
- Alert if recycler is empty (potential memory pressure)
- Track concurrent transfer efficiency

---

## Receiver Metrics (`lidi-receive`)

### Counter: `lidi_receive_blocks_reassembled`

**Type:** Counter

**Description:** Total number of RaptorQ blocks successfully reassembled (decoded) since startup.

**Units:** Blocks

**Interpretation:**
- One per complete RaptorQ block (contains up to `block_size` bytes)
- Increases when enough packets are received to reconstruct a block
- Does NOT count heartbeat blocks

**Usage:**
- Track data delivery rate
- Monitor decoding performance
- Calculate blocks/sec throughput

---

### Counter: `lidi_receive_blocks_decoded`

**Type:** Counter

**Description:** Total number of RaptorQ blocks successfully decoded using repair packets.

**Units:** Blocks

**Interpretation:**
- Subset of `blocks_reassembled`
- Counts ONLY blocks that required repair packet usage
- High value = high packet loss tolerance in action

**Usage:**
- Monitor packet loss impact
- Verify repair functionality works
- Track FEC (Forward Error Correction) necessity

---

### Counter: `lidi_receive_blocks_decode_failed`

**Type:** Counter

**Description:** Total number of RaptorQ blocks that failed to decode despite repair packets.

**Units:** Blocks

**Interpretation:**
- Blocks lost due to packet loss exceeding repair capacity
- Indicates data corruption on this transfer
- Occurs when (packets_received < symbol_count + 2)

**Usage:**
- Alert on any increment (indicates data loss)
- Monitor network reliability
- Tune `repair` parameter if this counter increments

---

### Counter: `lidi_receive_blocks_lost`

**Type:** Counter

**Description:** Total number of RaptorQ blocks abandoned without attempting decode.

**Units:** Blocks

**Interpretation:**
- Blocks discarded due to timeout or explicit abort
- Different from `blocks_decode_failed` (not even attempted)
- Occurs when `reset_timeout` expires on incomplete block

**Usage:**
- Monitor for network interruptions
- Alert on frequent increments
- Adjust `reset_timeout` if this is too high

---

### Counter: `lidi_receive_blocks_for_inactive_client`

**Type:** Counter

**Description:** Total number of blocks received for inactive/unknown clients.

**Units:** Blocks

**Interpretation:**
- Blocks with invalid `client_id` or client already closed
- May indicate out-of-order packets or sender/receiver desync

**Usage:**
- Detect protocol violations
- Monitor for multicast/broadcast leakage
- Alert if non-zero

---

### Counter: `lidi_receive_heartbeat_missed`

**Type:** Counter

**Description:** Total number of missed heartbeat intervals detected.

**Units:** Intervals

**Interpretation:**
- Increments when expected heartbeat doesn't arrive within timeout
- Indicates sender disconnection or severe network delay
- Only incremented if heartbeat is enabled (`heartbeat > 0`)

**Usage:**
- Monitor sender availability
- Detect network partitions
- Alert on any increment (indicates connection loss)

---

### Counter: `lidi_receive_packets_ignored`

**Type:** Counter

**Description:** Total number of UDP packets dropped/ignored (not processed).

**Units:** Packets

**Interpretation:**
- Packets for completed/unknown blocks
- Packets with invalid format
- Packets arriving after block timeout

**Usage:**
- Detect late arrivals (packets arriving after block timeout)
- Monitor for out-of-order delivery issues
- Track duplicate/unnecessary packets

---

### Counter: `lidi_receive_client_queue_full`

**Type:** Counter

**Description:** Total number of times a client's decode queue reached capacity.

**Units:** Events

**Interpretation:**
- Increments when incoming blocks exceed `queue_size` limit per client
- Indicates receiver buffer overflow or slow TCP output path
- Causes packet loss if queue is full and packets dropped

**Usage:**
- Alert if queue_full occurs (indicates backpressure)
- Monitor for TCP output bottleneck
- Tune `queue_size` parameter

---

### Gauge: `lidi_receive_reblock_queue_len`

**Type:** Gauge

**Description:** Current number of blocks in the reblocking queue.

**Units:** Blocks

**Interpretation:**
- Blocks received out-of-order, waiting for missing predecessors
- Part of the sliding window reordering mechanism
- Should be <= `WINDOW_WIDTH` (128 blocks)

**Usage:**
- Monitor out-of-order delivery severity
- Alert if queue consistently high
- Track network reordering patterns

---

### Gauge: `lidi_receive_decode_queue_len`

**Type:** Gauge

**Description:** Current number of blocks awaiting RaptorQ decoding.

**Units:** Blocks

**Interpretation:**
- Blocks with received packets, but not yet decoded
- Indicates decoding backlog
- High value = slow decoding or fast reception

**Usage:**
- Monitor decoding throughput
- Detect CPU bottleneck in RaptorQ
- Track queue buildup

---

### Gauge: `lidi_receive_dispatch_queue_len`

**Type:** Gauge

**Description:** Current number of decoded blocks waiting for TCP output.

**Units:** Blocks

**Interpretation:**
- Decoded blocks pending TCP transmission to client
- Indicates TCP output bottleneck
- High value = slow client reading or low bandwidth

**Usage:**
- Monitor TCP output backlog
- Detect client connection slowdown
- Track application latency

---

### Histogram: `lidi_receive_decode_with_n_packets`

**Type:** Histogram

**Description:** Distribution of packet counts used to decode each block.

**Buckets:** 
- `le="+"` = total count
- Exponential buckets from 2 to 256+ packets

**Example:**
```
lidi_receive_decode_with_n_packets_bucket{le="8"} 100
lidi_receive_decode_with_n_packets_bucket{le="16"} 150
lidi_receive_decode_with_n_packets_bucket{le="+Inf"} 200
lidi_receive_decode_with_n_packets_sum 2400
lidi_receive_decode_with_n_packets_count 200
```

**Interpretation:**
- Shows how many packets (source + repair) were needed per block
- Lower buckets = minimal repair usage (good network)
- Higher buckets = more repair packets required (lossy network)
- `_sum` / `_count` = average packets per block

**Usage:**
- Characterize network packet loss distribution
- Verify repair packets are effective
- Tune RaptorQ `repair` percentage based on distribution

---

## Example: Full Metrics Scrape

```
# HELP lidi_send_udp_packets Total UDP packets sent
# TYPE lidi_send_udp_packets counter
lidi_send_udp_packets 32672

# HELP lidi_send_udp_queue_len Current UDP send queue length
# TYPE lidi_send_udp_queue_len gauge
lidi_send_udp_queue_len 1

# HELP lidi_send_block_recycler_len Available block buffers
# TYPE lidi_send_block_recycler_len gauge
lidi_send_block_recycler_len 3

# HELP lidi_receive_blocks_reassembled Total blocks reassembled
# TYPE lidi_receive_blocks_reassembled counter
lidi_receive_blocks_reassembled 152

# HELP lidi_receive_blocks_decoded Blocks decoded with repair packets
# TYPE lidi_receive_blocks_decoded counter
lidi_receive_blocks_decoded 8

# HELP lidi_receive_blocks_decode_failed Failed block decodes
# TYPE lidi_receive_blocks_decode_failed counter
lidi_receive_blocks_decode_failed 0

# HELP lidi_receive_blocks_lost Abandoned blocks (timeout)
# TYPE lidi_receive_blocks_lost counter
lidi_receive_blocks_lost 0

# HELP lidi_receive_heartbeat_missed Missed heartbeat intervals
# TYPE lidi_receive_heartbeat_missed counter
lidi_receive_heartbeat_missed 0

# HELP lidi_receive_decode_with_n_packets Packets used to decode blocks
# TYPE lidi_receive_decode_with_n_packets histogram
lidi_receive_decode_with_n_packets_bucket{le="2"} 0
lidi_receive_decode_with_n_packets_bucket{le="4"} 42
lidi_receive_decode_with_n_packets_bucket{le="8"} 100
lidi_receive_decode_with_n_packets_bucket{le="16"} 150
lidi_receive_decode_with_n_packets_bucket{le="+Inf"} 152
lidi_receive_decode_with_n_packets_sum 2400
lidi_receive_decode_with_n_packets_count 152
```

---

## Common Alerting Rules

### Alert: Sender stuck (no packets sent)

```promql
# No packets sent in last 5 minutes
increase(lidi_send_udp_packets[5m]) == 0
```

### Alert: Receiver data loss

```promql
# Any blocks failed to decode
increase(lidi_receive_blocks_decode_failed[5m]) > 0
```

### Alert: Network unreliability

```promql
# More than 10% packet loss (repair usage high)
(lidi_receive_blocks_decoded / lidi_receive_blocks_reassembled) > 0.1
```

### Alert: TCP output bottleneck

```promql
# Dispatch queue growing
increase(lidi_receive_dispatch_queue_len[2m]) > 10
```

---

## Testing Metrics

Run the Prometheus test suite:

```bash
behave features/prometheus.feature
```

This verifies:
- Prometheus endpoints respond (T15.1)
- Metrics are incremented after transfer (T15.2, T15.4)
- Metrics available under network conditions (T15.5, T15.6)
