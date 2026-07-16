Feature: lidi-file-receive behaviour (receiver-side edge cases)
  # Tests the lidi-receive → lidi-file-receive link.
  # Complement to multi_client.feature which covers lidi-file-send → lidi-send.
  #
  # Key architectural facts:
  #   - lidi-file-receive is the TCP SERVER; lidi-receive is the TCP CLIENT.
  #   - lidi-receive connects to lidi-file-receive once per Start block (per transfer).
  #     If the connection is refused, the client worker exits immediately — no retry.
  #   - lidi-receive spawns max_clients worker threads at startup (pre-allocated pool).
  #     Each thread loops: pick next client from for_clients queue, handle it, repeat.
  #   - A worker thread is "free" only after client::start() returns (write_all returns).
  #   - abort_timeout is on the recvq.recv() side — it does NOT unblock a stuck write_all().
  #   - queue_size guards dispatch → worker channel; overflow kills the channel entry in
  #     active_transfers, but the worker thread remains stuck until write_all() returns.

  # ---------------------------------------------------------------------------
  # Group A — Timing of connection (inverse of sender side)
  # ---------------------------------------------------------------------------

  Scenario: T-FRC-A1 — no lidi-file-receive: connection refused, lidi-receive survives
    # lidi-receive connects to port 6000 when it receives the Start block.
    # With nothing listening on 6000: TcpStream::connect() → ECONNREFUSED → worker exits.
    # lidi-receive continues running. Contrast with sender side: lidi-send always waits
    # for lidi-file-send to connect; here the server must exist BEFORE the transfer begins.
    Given lidi is started without lidi-file-receive and limited to 800kbit
    When file "input_100k" of size 100KB is sent
    Then file "input_100k" should not exist after 10 seconds
    And lidi-receive should still be running

  Scenario: T-FRC-A2 — lidi-file-receive starts too late: connection refused, no retry
    # The Start block arrives and lidi-receive immediately calls TcpStream::connect().
    # There is no retry mechanism: connection refused → worker exits → file lost.
    # Starting lidi-file-receive 3s later proves there is no deferred retry.
    Given lidi is started without lidi-file-receive and limited to 800kbit
    When file "input_100k" of size 100KB is sent
    And lidi-file-receive is started 3 seconds later
    Then file "input_100k" should not exist after 10 seconds
    And lidi-receive should still be running

  Scenario: T-FRC-A3 — max_files=1: second transfer refused after lidi-file-receive exits
    # lidi-file-receive exits its accept() loop after max_files files are received.
    # The second transfer arrives on a closed TCP port → ECONNREFUSED → worker exits.
    # Tests the lifecycle boundary when lidi-file-receive is intentionally finite.
    Given lidi is started without lidi-file-receive, with max_clients 1 and limited to 800kbit
    And lidi-file-receive is started with max_files set to 1
    When file "input_100k_1" of size 100KB is sent
    Then lidi-file-receive file "input_100k_1" in 15 seconds
    When file "input_100k_2" of size 100KB is sent
    Then file "input_100k_2" should not exist after 10 seconds
    And lidi-receive should still be running

  # ---------------------------------------------------------------------------
  # Group B — lidi-file-receive failure during reception
  # ---------------------------------------------------------------------------

  Scenario: T-FRC-B1 — kill lidi-file-receive mid-transfer: broken pipe leaves a partial file on disk
    # Killing lidi-file-receive closes the TCP socket. The next write_all() in lidi-receive
    # returns EPIPE. The client worker exits, the pre-allocated thread loops back to
    # for_clients.recv() and is ready for the next transfer. lidi-receive stays running.
    #
    # Root cause (lidi-clients/src/file/receive.rs):
    #   Without --use-tmp-file, receive_file() opens the final output file directly with
    #   OpenOptions::create(true).truncate(true) as soon as the header is received. When
    #   lidi-file-receive is killed (SIGKILL), the OS closes the TCP socket;
    #   receive_file() returns Err(InvalidFileSize) and the partial (possibly 0-byte)
    #   output file is left in place under its final name.
    # Fix: use --use-tmp-file to write atomically via a temporary file. See T-FRC-B1-FIXED.
    Given lidi is started with max_clients set to 1 and limited to 800kbit
    When client 1 starts sending "input_1m" of size 1MB
    And lidi-file-receive is killed after 2 seconds
    And 5 seconds are waited for slot release
    Then lidi-receive should still be running
    # Demonstrates the defect: a partial "input_1m" is left under its final name
    And file "input_1m" of size 1MB should remain on disk as an incomplete file

  Scenario: T-FRC-B1-FIXED — kill lidi-file-receive mid-transfer with --use-tmp-file (atomic write)
    # Same as T-FRC-B1 but with --use-tmp-file enabled. Content is written to a uniquely
    # named temporary file (via tempfile::NamedTempFile) and persisted atomically on
    # success. If the process is killed mid-transfer, "input_1m" never exists in a
    # partial state — only the orphaned .tmp file remains (cleaned up automatically on
    # the next lidi-file-receive startup), which is harmless.
    Given lidi-file-receive uses atomic tmp file writes
    And lidi is started with max_clients set to 1 and limited to 800kbit
    When client 1 starts sending "input_1m" of size 1MB
    And lidi-file-receive is killed after 2 seconds
    And 5 seconds are waited for slot release
    Then lidi-receive should still be running
    And file "input_1m" should not be received

  Scenario: T-FRC-B2 — sender stopped mid-transfer: partial file must be removed
    # Tests the scenario where the sender (lidi-send) stops mid-transfer, not the
    # receiver. Unlike killing lidi-file-receive (SIGKILL), stopping lidi-send allows
    # the transfer to fail gracefully on the receiver side.
    #
    # Mechanism:
    #   1. lidi-file-send sends to lidi-send over loopback TCP (no rate limit)
    #   2. lidi-send buffers the entire file in milliseconds
    #   3. Stopping lidi-send stops UDP transmission
    #   4. After reset_timeout (2s), lidi-receive's block channel closes
    #   5. Worker exits → TCP to lidi-file-receive closes → diode.read() returns 0
    #   6. receive_file() returns Err(InvalidFileSize) with remaining > 0
    #
    # Root cause fix (commit 433ae0d):
    #   receive_file() wraps write_file_content() in a match statement and calls
    #   fs::remove_file() in the Err branch. This removes the partially written
    #   file before returning the error, preventing incomplete files from being
    #   mistaken for successfully received ones.
    Given lidi is started with max_clients set to 1 and limited to 800kbit
    When client 1 starts sending "input_1m" of size 1MB
    And 2 seconds are waited for slot release
    And lidi-send is stopped
    And 6 seconds are waited for slot release
    Then file "input_1m" should not be received
    And lidi-file-receive log should report an error for an incomplete transfer
    And lidi-receive should still be running

  Scenario: T-FRC-B3 — SIGSTOP lidi-file-receive: write_all blocks, slot never freed
    # Root cause (lidi-receive/src/client.rs): write_all() has no TCP write timeout.
    # When lidi-file-receive stops reading (SIGSTOP), the OS TCP receive buffer fills,
    # TCP flow control stalls lidi-receive, and write_all() blocks indefinitely.
    # - abort_timeout guards recvq.recv_timeout() — fires only when the worker is WAITING
    #   for new blocks; it never fires when the worker is stuck inside write_all().
    # - queue_size overflow removes the client from active_transfers (no new blocks queued)
    #   but the worker thread remains blocked on write_all(): the slot is NOT freed.
    # Consequence: with max_clients=1, a SIGSTOPped lidi-file-receive permanently
    # occupies the only worker thread. Subsequent transfers stall indefinitely.
    # Fix: add SO_SNDTIMEO (TCP write timeout) to the client socket in client.rs.
    Given lidi is started with max_clients set to 1 and limited to 800kbit
    When client 1 starts sending "input_1m" of size 1MB
    And lidi-file-receive is suspended after 1 seconds
    And 5 seconds are waited for slot release
    And file "input_100k_follow" of size 100KB is sent
    Then file "input_100k_follow" should not be received
    And lidi-receive should still be running

  # ---------------------------------------------------------------------------
  # Group Q — queue_size and backpressure
  # ---------------------------------------------------------------------------

  Scenario: T-FRC-Q1 — queue_size=1, SIGSTOP: dispatch drops client but slot stays occupied
    # With queue_size=1: when lidi-file-receive stops reading, write_all() blocks,
    # the worker cannot drain recvq. The 2nd block try_send() fails → dispatch removes
    # the client from active_transfers (correct: no more data piles up in memory).
    # BUT the worker thread is still blocked on write_all() → the max_clients slot is
    # NOT freed. Subsequent transfers are queued in to_clients but no worker picks them up.
    # queue_size protects memory (caps buffering) but does NOT free the execution slot.
    # Same root cause as T-FRC-B3: no TCP write timeout in client.rs.
    Given lidi-receive is configured with queue_size of 1
    And lidi is started with max_clients set to 1 and limited to 800kbit
    When client 1 starts sending "input_1m" of size 1MB
    And lidi-file-receive is suspended after 1 seconds
    And 5 seconds are waited for slot release
    And file "input_100k_follow" of size 100KB is sent
    Then file "input_100k_follow" should not be received
    And lidi-receive should still be running

  Scenario: T-FRC-Q2 — queue_size=0 (unbounded), temporary stall: file received after resume
    # With unbounded queue and a temporary SIGSTOP, lidi-receive buffers decoded blocks
    # in memory during the stall period. After SIGCONT, lidi-file-receive resumes reading,
    # drains the TCP buffers, and the recvq empties. The file arrives intact.
    # Validates that a temporary backpressure event does not corrupt or kill the transfer
    # (contrast with T-FRC-Q1 where queue_size=1 causes the transfer to be killed).
    Given lidi-receive is configured with queue_size of 0
    And lidi is started with max_clients set to 1 and limited to 800kbit
    When client 1 starts sending "input_1m" of size 1MB
    And lidi-file-receive is suspended after 1 seconds
    And 3 seconds are waited for slot release
    And lidi-file-receive is resumed
    Then lidi-file-receive file "input_1m" in 30 seconds

  # ---------------------------------------------------------------------------
  # Group D — deficit and surplus of lidi-file-receive instances
  # ---------------------------------------------------------------------------

  Scenario: T-FRC-D1 — 1 lidi-file-receive instance serves 3 simultaneous transfers
    # lidi-file-receive loops accept() + scope.spawn(): each connection is handled in a
    # separate thread and accept() returns immediately to take the next connection.
    # One instance is sufficient for any number of parallel transfers (up to max_clients).
    # Validates a common misconception: N transfers do NOT require N instances.
    Given lidi is started with max_clients set to 3 and limited to 800kbit
    When 3 clients are launched concurrently sending "input_100k_1", "input_100k_2", "input_100k_3" of size 100KB each
    Then lidi-file-receive file "input_100k_1" in 30 seconds
    And lidi-file-receive file "input_100k_2" in 30 seconds
    And lidi-file-receive file "input_100k_3" in 30 seconds

  Scenario: T-FRC-D2 — 0 lidi-file-receive instances: all transfers fail gracefully
    # Same mechanism as T-FRC-A1 but with 2 concurrent workers both failing.
    # Validates that multiple simultaneous ECONNREFUSED errors do not crash lidi-receive.
    Given lidi is started without lidi-file-receive and limited to 800kbit
    When 2 clients are launched concurrently sending "input_100k_1", "input_100k_2" of size 100KB each
    Then file "input_100k_1" should not exist after 15 seconds
    And file "input_100k_2" should not exist after 15 seconds
    And lidi-receive should still be running

  # ---------------------------------------------------------------------------
  # Group R — reconnection and slot lifecycle (receiver side)
  # ---------------------------------------------------------------------------

  Scenario: T-FRC-R1 — broken pipe frees slot: second transfer succeeds after lidi-file-receive restart
    # When lidi-file-receive is killed (SIGKILL), write_all() returns EPIPE, the worker
    # exits client::start(), and the thread loops back to for_clients.recv() (slot freed).
    # A new lidi-file-receive restarted before the second transfer can accept the next
    # connection from lidi-receive. Validates slot reuse after receiver-side broken pipe.
    # Symmetric to T-MC-R2 (slot freed by Abort on sender side) but triggered on receiver side.
    Given lidi is started with max_clients set to 1 and limited to 800kbit
    When client 1 starts sending "input_1m" of size 1MB
    And lidi-file-receive is killed after 2 seconds
    And 5 seconds are waited for slot release
    And lidi-file-receive is restarted
    And file "input_100k_final" of size 100KB is sent
    Then lidi-file-receive file "input_100k_final" in 15 seconds

  Scenario: T-FRC-R3 — no slot leak after 3 consecutive broken pipe cycles
    # Three successive kill → restart cycles must not exhaust the worker pool.
    # After each SIGKILL, EPIPE unblocks the worker which loops back to for_clients.
    # Validates there is no per-cycle resource leak on the receive side.
    # Symmetric to T-MC-R4 (no slot leak on sender side) but triggered by receiver kills.
    Given lidi is started with max_clients set to 2 and limited to 800kbit
    When client 1 starts sending "input_1m_1" of size 1MB
    And lidi-file-receive is killed after 2 seconds
    And 5 seconds are waited for slot release
    And lidi-file-receive is restarted
    And client 2 starts sending "input_1m_2" of size 1MB
    And lidi-file-receive is killed after 2 seconds
    And 5 seconds are waited for slot release
    And lidi-file-receive is restarted
    And client 3 starts sending "input_1m_3" of size 1MB
    And lidi-file-receive is killed after 2 seconds
    And 5 seconds are waited for slot release
    And lidi-file-receive is restarted
    And file "input_100k_final" of size 100KB is sent
    Then lidi-file-receive file "input_100k_final" in 15 seconds

  # ---------------------------------------------------------------------------
  # Group W — file write errors
  # ---------------------------------------------------------------------------

  Scenario: T-FRC-W1 — read-only output directory: open() fails, lidi-receive survives
    # lidi-file-receive calls fs::OpenOptions::open() to create the output file.
    # With output_dir chmod 555 (no write permission), open() returns EACCES.
    # receive_file() returns Err → the spawned thread exits → TCP socket dropped.
    # lidi-receive's write_all() gets EPIPE on subsequent bytes → worker exits cleanly.
    # Validates that an application-level write error (not a network error) is handled
    # gracefully and does not crash lidi-receive or leak its slot.
    Given lidi is started with max_clients set to 1 and limited to 800kbit
    And lidi-file-receive output directory is read-only
    When file "input_100k" of size 100KB is sent
    Then file "input_100k" should not exist after 10 seconds
    And lidi-receive should still be running
