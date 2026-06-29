Feature: Multi-client support (max_clients parameter)

  # Group 0: Degenerate case max_clients=0
  Scenario: T-MC0.1 — max_clients=0 — neither lidi-send nor lidi-receive starts
    Given lidi-send fails to start with max_clients set to 0
    And lidi-receive fails to start with max_clients set to 0

  # Group 1: max_clients=1 (serial processing)
  Scenario: T-MC1.1 — max_clients=1 — nominal case 1 client
    Given lidi is started with max_clients set to 1 and limited to 8mbit
    When file "input_100k" of size 100KB is sent
    Then lidi-file-receive file "input_100k" in 10 seconds

  Scenario: T-MC1.2 — max_clients=1 — 2 simultaneous clients
    # Timeout waiting for second file. With 1 worker handling 2 sequential clients,
    # files queue but reception times out. Possible causes: (a) bounded to_server channel
    # not properly passing connections, (b) slow receipt, or (c) RaptorQ/reblocking delays.
    # Investigate: lidi-send worker recv() loop, client connection queuing, timing.
    Given lidi is started with max_clients set to 1 and limited to 8mbit
    When 2 clients are launched concurrently sending "input_100k_1", "input_100k_2" of size 100KB each
    Then lidi-file-receive file "input_100k_1" in 10 seconds
    And lidi-file-receive file "input_100k_2" in 10 seconds

  Scenario: T-MC1.3 — max_clients=1 — 3 simultaneous clients
    # Similar to T-MC1.2: timeout on subsequent files. Sequential reception with 1 worker
    # should work but files timeout. Suspect timing/queueing in worker loop.
    Given lidi is started with max_clients set to 1 and limited to 8mbit
    When 3 clients are launched concurrently sending "input_100k_1", "input_100k_2", "input_100k_3" of size 100KB each
    Then lidi-file-receive file "input_100k_1" in 10 seconds
    And lidi-file-receive file "input_100k_2" in 10 seconds
    And lidi-file-receive file "input_100k_3" in 10 seconds

  # Group 2: max_clients=2 (nominal parallelism)
  Scenario: T-MC2.1 — max_clients=2 — nominal case 1 client
    Given lidi is started with max_clients set to 2 and limited to 8mbit
    When file "input_100k" of size 100KB is sent
    Then lidi-file-receive file "input_100k" in 10 seconds

  Scenario: T-MC2.2 — max_clients=2 — 2 clients in parallel
    # Timeout on parallel clients. With 2 workers, both clients should run in parallel
    # but files timeout. May indicate issue with worker thread scheduling or packet
    # handling when multiple clients active simultaneously.
    Given lidi is started with max_clients set to 2 and limited to 8mbit
    When 2 clients are launched concurrently sending "input_100k_1", "input_100k_2" of size 100KB each
    Then lidi-file-receive file "input_100k_1" in 10 seconds
    And lidi-file-receive file "input_100k_2" in 10 seconds

  Scenario: T-MC2.3 — max_clients=2 — 4 clients with 2 workers (overflow)
    # Similar to T-MC2.2: timeouts with multiple clients. With queueing (2 workers,
    # 4 clients), may indicate issue in worker's retry/queue processing after finishing
    # first batch. Investigate: queue_size handling, worker loop continuation.
    Given lidi is started with max_clients set to 2 and limited to 8mbit
    When 4 clients are launched concurrently sending "input_100k_1", "input_100k_2", "input_100k_3", "input_100k_4" of size 100KB each
    Then lidi-file-receive file "input_100k_1" in 15 seconds
    And lidi-file-receive file "input_100k_2" in 15 seconds
    And lidi-file-receive file "input_100k_3" in 15 seconds
    And lidi-file-receive file "input_100k_4" in 15 seconds

  Scenario: T-MC2.4 — max_clients=2 — isolation client 1 killed doesn't affect client 2
    # Client 1 sends a 5MB file: on loopback this is large enough that
    # lidi-file-send is still blocked writing to the socket (backpressure from
    # the throttled UDP link) when it gets killed after 1 second, so the
    # transfer is genuinely interrupted mid-stream rather than already
    # finished. At 8mbit with 2 clients (~500KB/s each), the ~2MB TCP buffer
    # drains in ~4s; the 30s grace period of "should not be received" covers
    # this comfortably with a small 200KB file for client 2.
    Given lidi is started with max_clients set to 2 and limited to 8mbit
    When client 1 starts sending "input_5m_1" of size 5MB
    And client 2 starts sending "input_200k_2" of size 200KB
    And client 1 is killed after 1 seconds
    Then lidi-file-receive file "input_200k_2" in 10 seconds
    And file "input_5m_1" should not be received

  # Group 10: max_clients=10 (high parallelization)
  Scenario: T-MC10.1 — max_clients=10 — 10 simultaneous clients
    # 10 × 100KB at 8mbit: each file is 1 RaptorQ block (220KB); bounded(1) channel
    # serialises them → 10 turns × 0.22s/block ≈ 2.2s for all transfers.
    Given lidi is started with max_clients set to 10 and limited to 8mbit
    When 10 clients are launched concurrently sending files of size 100KB each
    Then all 10 output files exist and are identical within 15 seconds

  Scenario: T-MC10.2 — max_clients=10 — minimal case with high config
    Given lidi is started with max_clients set to 10 and limited to 8mbit
    When file "input_100k" of size 100KB is sent
    Then lidi-file-receive file "input_100k" in 10 seconds

  # Group R: Slot lifecycle (reconnection)
  Scenario: T-MC-R1 — max_clients=1 — sequential reconnection slot freed 3x
    # Sequential reconnection timeout: files timeout on 2nd and 3rd transfers.
    # After EOF on first transfer, worker should loop and accept next connection.
    # Issue: slot not properly freed or worker stuck. Investigate: TCP EOF handling,
    # worker loop continuation after client disconnect, connection acceptance.
    Given lidi is started with max_clients set to 1 and limited to 8mbit
    When 3 sequential file transfers of "input_seq_1", "input_seq_2", "input_seq_3" of size 100KB are executed
    Then lidi-file-receive file "input_seq_1" in 10 seconds
    And lidi-file-receive file "input_seq_2" in 10 seconds
    And lidi-file-receive file "input_seq_3" in 10 seconds

  Scenario: T-MC-R2 — max_clients=1 — slot freed after Abort (client killed)
    # Client 1 sends a 5MB file: large enough that lidi-file-send is still
    # blocked writing to the socket (backpressure from the throttled UDP
    # link) when it gets killed after 1 second, so the transfer is genuinely
    # interrupted mid-stream. At 8mbit (1MB/s), the ~2MB TCP buffer drains
    # in ~2s; the 3s wait covers propagation before the follow-up is sent.
    Given lidi is started with max_clients set to 1 and limited to 8mbit
    When client 1 starts sending "input_5m" of size 5MB
    And client 1 is killed after 1 seconds
    And 3 seconds are waited for Abort propagation
    And file "input_100k_follow" of size 100KB is sent
    Then lidi-file-receive file "input_100k_follow" in 15 seconds
    And file "input_5m" should not be received

  Scenario: T-MC-R3 — max_clients=1 bandwidth limited — respects queue not reject
    # Two concurrent clients with max_clients=1: second client queues in to_server
    # channel and is processed after the first completes. At 8mbit (1MB/s),
    # 100KB = 0.1s per file; two sequential = ~0.2s, well within the 10s timeout.
    Given lidi is started with max_clients set to 1 and limited to 8mbit
    When 2 clients are launched concurrently sending "input_100k_1", "input_100k_2" of size 100KB each
    Then lidi-file-receive file "input_100k_1" in 10 seconds
    And lidi-file-receive file "input_100k_2" in 10 seconds

  Scenario: T-MC-R4 — max_clients=2 — no slot leak after multiple Abort cycles (abort_timeout=1s)
    Given abort_timeout is set to 1 second
    And lidi is started with max_clients set to 2 and limited to 8mbit
    When client 1 starts sending "input_200k_1" of size 200KB
    And client 1 is killed after 1 seconds
    And 2 seconds are waited for Abort propagation
    And client 2 starts sending "input_200k_2" of size 200KB
    And client 2 is killed after 1 seconds
    And 2 seconds are waited for Abort propagation
    And client 3 starts sending "input_200k_3" of size 200KB
    And client 3 is killed after 1 seconds
    And 2 seconds are waited for Abort propagation
    And file "input_100k_final" of size 100KB is sent
    Then lidi-file-receive file "input_100k_final" in 10 seconds

  # Group ISO: Isolation of large transfer
  Scenario: T-MC-ISO1 — max_clients=10 — large transfer unaffected by 5 concurrent crashes
    Given lidi is started with max_clients set to 10 and limited to 8mbit
    When client 1 starts sending "input_200k" of size 200KB
    And 5 additional clients start sending "input_1k_*" of size 1KB each
    And clients 2-6 are killed after 1 seconds
    Then lidi-file-receive file "input_200k" in 10 seconds

  Scenario: T-MC-ISO2 — max_clients=10 — large transfer coexisting with 5 normal small transfers
    Given lidi is started with max_clients set to 10 and limited to 8mbit
    When client 1 starts sending "input_200k" of size 200KB
    And 5 additional clients start sending "input_100k_*" of size 100KB each
    Then lidi-file-receive file "input_200k" in 10 seconds
    And all 5 additional output files exist and are identical within 10 seconds

  Scenario: T-MC-ISO3 — max_clients=3 — large transfer unaffected by Abort and normal concurrent
    # Client 2 sends a 5MB file: large enough that lidi-file-send is still
    # blocked writing to the socket (backpressure from the throttled UDP
    # link) when it gets killed after 1 second, so the transfer is genuinely
    # interrupted mid-stream. At 8mbit shared across 3 clients (~334KB/s
    # each), the ~2MB TCP buffer drains in ~6s; the 30s grace period of
    # "should not be received" (starting at ~t=1s after fast client 1 + 3
    # transfers) covers this comfortably.
    Given lidi is started with max_clients set to 3 and limited to 8mbit
    When client 1 starts sending "input_200k_1" of size 200KB
    And client 2 starts sending "input_5m_2" of size 5MB
    And client 3 starts sending "input_100k" of size 100KB
    And client 2 is killed after 1 seconds
    Then lidi-file-receive file "input_200k_1" in 10 seconds
    And lidi-file-receive file "input_100k" in 10 seconds
    And file "input_5m_2" should not be received
