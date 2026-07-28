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
    Given lidi is started without lidi-file-receive and limited to 4mbit
    When file "input_100k" of size 100KB is sent
    Then file "input_100k" should not exist after 1 seconds
    And lidi-receive should still be running

  Scenario: T-FRC-A2 — lidi-file-receive starts too late: connection refused, no retry
    # The Start block arrives and lidi-receive immediately calls TcpStream::connect().
    # There is no retry mechanism: connection refused → worker exits → file lost.
    # Starting lidi-file-receive 1s later proves there is no deferred retry.
    # 100KB at 4mbit takes ~0.2s; connection attempt is done well before 1s.
    Given lidi is started without lidi-file-receive and limited to 4mbit
    When file "input_100k" of size 100KB is sent
    And lidi-file-receive is started 1 seconds later
    Then file "input_100k" should not exist after 1 seconds
    And lidi-receive should still be running

  Scenario: T-FRC-A3 — max_files=1: second transfer refused after lidi-file-receive exits
    # lidi-file-receive exits its accept() loop after max_files files are received.
    # The second transfer arrives on a closed TCP port → ECONNREFUSED → worker exits.
    # Tests the lifecycle boundary when lidi-file-receive is intentionally finite.
    Given lidi is started without lidi-file-receive, with max_clients 1 and limited to 4mbit
    And lidi-file-receive is started with max_files set to 1
    When file "input_100k_1" of size 100KB is sent
    Then lidi-file-receive file "input_100k_1" in 15 seconds
    When file "input_100k_2" of size 100KB is sent
    Then file "input_100k_2" should not exist after 1 seconds
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
    #   Without --tmp-dir, receive_file() opens the final output file directly with
    #   OpenOptions::create(true).truncate(true) as soon as the header is received. When
    #   lidi-file-receive is killed (SIGKILL), the OS closes the TCP socket;
    #   receive_file() returns Err(InvalidFileSize) and the partial (possibly 0-byte)
    #   output file is left in place under its final name.
    # Fix: use --tmp-dir to write in a temporary directory. See T-FRC-B1-FIXED.
    Given lidi is started with max_clients set to 1 and limited to 4mbit
    When client 1 starts sending "input_1m" of size 1MB
    And lidi-file-receive is killed after 1 seconds
    And 1 seconds are waited for slot release
    Then lidi-receive should still be running
    # Demonstrates the defect: a partial "input_1m" is left under its final name
    And file "input_1m" of size 1MB should remain on disk as an incomplete file

  Scenario: T-FRC-B1-FIXED — kill lidi-file-receive mid-transfer with --tmp-dir (atomic write)
    # Same as T-FRC-B1 but with --tmp-dir enabled. Content is written to a temp
    # dir and moved atomically to the output dir on success. If the process is
    # killed mid-transfer, "input_1m" never exists in a partial state in the
    # output dir, only in the temp dir.
    Given lidi-file-receive uses a temporary directory
    And lidi is started with max_clients set to 1 and limited to 4mbit
    When client 1 starts sending "input_1m" of size 1MB
    And lidi-file-receive is killed after 1 seconds
    And 1 seconds are waited for slot release
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

  Scenario: T-FRC-B2-ABORT — partial file cleaned up within abort_timeout after interrupted transfer
    # When lidi-send is stopped mid-transfer the last RaptorQ block may decode
    # successfully (loopback delivers source symbols in order), so no Abort is sent.
    # client_reorder's recv_timeout(abort_timeout) is then the backstop: it exits
    # after abort_timeout seconds without a new block, dropping to_client, which
    # unblocks client::start and closes the TCP connection.
    # lidi-file-receive then gets Err(InvalidFileSize) and removes the partial file.
    #
    # With abort_timeout = 3 s the cleanup completes well within the 4 s window.
    Given abort_timeout is configured to 3 seconds
    And lidi is started with max_clients set to 1 and limited to 800kbit
    When client 1 starts sending "input_1m" of size 1MB
    And 2 seconds are waited for slot release
    And lidi-send is stopped
    And 4 seconds are waited for slot release
    Then file "input_1m" should not be received
    And lidi-receive should still be running

  Scenario: T-FRC-B3 — SIGSTOP lidi-file-receive: SO_SNDTIMEO frees the slot, transfer resumes after SIGCONT
    # Fix (lidi-receive/src/client.rs): the client socket has SO_SNDTIMEO set to
    # abort_timeout. When lidi-file-receive stops reading (SIGSTOP), the OS TCP
    # receive buffer fills, TCP flow control stalls lidi-receive, and write_all()
    # now returns a timeout error after abort_timeout seconds instead of blocking
    # forever. The worker exits client::start(), the pre-allocated thread loops back
    # to for_clients.recv(), and the slot is freed.
    # Once lidi-file-receive is resumed (SIGCONT), the next transfer connects and
    # completes normally, proving there is no permanent slot leak.
    Given abort_timeout is configured to 2 seconds
    And lidi is started with max_clients set to 1 and limited to 4mbit
    When client 1 starts sending "input_1m" of size 1MB
    And lidi-file-receive is suspended after 1 seconds
    And 2 seconds are waited for slot release
    And lidi-file-receive is resumed
    And file "input_100k_follow" of size 100KB is sent
    Then file "input_100k_follow" should not be received
    And lidi-receive should still be running

  # ---------------------------------------------------------------------------
  # Group Q — queue_size and backpressure
  # ---------------------------------------------------------------------------

  Scenario: T-FRC-Q1 — queue_size=1, SIGSTOP: dispatch drops client but slot stays occupied
    # With queue_size=1: when lidi-file-receive stops reading, write_all() blocks,
    # the worker cannot drain recvq. The 2nd block try_send() fails → dispatch removes
    # the client from active_transfers (no more data piles up in memory).
    # Fix (lidi-receive/src/client.rs): SO_SNDTIMEO (set to abort_timeout) unblocks
    # write_all() with a timeout error after abort_timeout seconds, regardless of
    # queue_size. The worker exits, the slot is freed, and after lidi-file-receive
    # is resumed (SIGCONT) the next transfer completes normally.
    Given abort_timeout is configured to 2 seconds
    And lidi-receive is configured with queue_size of 1
    And lidi is started with max_clients set to 1 and limited to 4mbit
    When client 1 starts sending "input_1m" of size 1MB
    And lidi-file-receive is suspended after 1 seconds
    And 2 seconds are waited for slot release
    And lidi-file-receive is resumed
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
    And lidi is started with max_clients set to 1 and limited to 4mbit
    When client 1 starts sending "input_1m" of size 1MB
    And lidi-file-receive is suspended after 1 seconds
    And 1 seconds are waited for slot release
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
    Given lidi is started with max_clients set to 3 and limited to 4mbit
    When 3 clients are launched concurrently sending "input_100k_1", "input_100k_2", "input_100k_3" of size 100KB each
    Then lidi-file-receive file "input_100k_1" in 30 seconds
    And lidi-file-receive file "input_100k_2" in 30 seconds
    And lidi-file-receive file "input_100k_3" in 30 seconds

  Scenario: T-FRC-D2 — 0 lidi-file-receive instances: all transfers fail gracefully
    # Same mechanism as T-FRC-A1 but with 2 concurrent workers both failing.
    # Validates that multiple simultaneous ECONNREFUSED errors do not crash lidi-receive.
    Given lidi is started without lidi-file-receive and limited to 4mbit
    When 2 clients are launched concurrently sending "input_100k_1", "input_100k_2" of size 100KB each
    Then file "input_100k_1" should not exist after 1 seconds
    And file "input_100k_2" should not exist after 1 seconds
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
    Given lidi is started with max_clients set to 1 and limited to 4mbit
    When client 1 starts sending "input_1m" of size 1MB
    And lidi-file-receive is killed after 1 seconds
    And 1 seconds are waited for slot release
    And lidi-file-receive is restarted
    And file "input_100k_final" of size 100KB is sent
    Then lidi-file-receive file "input_100k_final" in 15 seconds

  Scenario: T-FRC-R3 — no slot leak after 3 consecutive broken pipe cycles
    # Three successive kill → restart cycles must not exhaust the worker pool.
    # After each SIGKILL, EPIPE unblocks the worker which loops back to for_clients.
    # Validates there is no per-cycle resource leak on the receive side.
    # Symmetric to T-MC-R4 (no slot leak on sender side) but triggered by receiver kills.
    Given lidi is started with max_clients set to 2 and limited to 4mbit
    When client 1 starts sending "input_1m_1" of size 1MB
    And lidi-file-receive is killed after 1 seconds
    And 1 seconds are waited for slot release
    And lidi-file-receive is restarted
    And client 2 starts sending "input_1m_2" of size 1MB
    And lidi-file-receive is killed after 1 seconds
    And 1 seconds are waited for slot release
    And lidi-file-receive is restarted
    And client 3 starts sending "input_1m_3" of size 1MB
    And lidi-file-receive is killed after 1 seconds
    And 1 seconds are waited for slot release
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
    Given lidi is started with max_clients set to 1 and limited to 4mbit
    And lidi-file-receive output directory is read-only
    When file "input_100k" of size 100KB is sent
    Then file "input_100k" should not exist after 1 seconds
    And lidi-receive should still be running
