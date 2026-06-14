Feature: Memory stability of lidi-send under congestion

  # Send-side pipeline memory analysis:
  #
  # to_server (lib.rs:203): bounded(1)           — no memory risk
  # to_udp    (lib.rs:204): bounded(ports.len()) — no memory risk
  #
  # Unlike the receive side (to_reblock/to_decode/to_dispatch are unbounded()),
  # all lidi-send queues are already bounded by design. When a consumer thread
  # is slow, backpressure propagates back to TCP with no memory accumulation.


  # ============================================================================
  # BASIC SEND TESTS — T-SS1 to T-SS3
  # ============================================================================

  Scenario: T-SS1 - Sender pipeline gauges are observable during transfer
    Given lidi is started with max throughput of 100mbit
    When lidi-file-send file tss1.bin of size 50MB
    Then the sender Prometheus gauge lidi_send_queue_len is greater than or equal to 1
    And the sender Prometheus gauge lidi_send_block_recycler_len is greater than or equal to 1
    And lidi-file-receive file tss1.bin in 15 seconds

  Scenario: T-SS2 - UDP queue is empty after transfer
    # to_udp is crossbeam_channel::bounded(ports.len()) = bounded(1) by default (lib.rs:204).
    # The metrics_loop updates gauges every 1 second (lib.rs:183). When the transfer ends,
    # to_udp drains to 0 immediately, but the Prometheus gauge lags by up to 1 second.
    # The step polls with retries to wait for the gauge to settle to 0.
    Given lidi is started with max throughput of 100mbit
    When lidi-file-send file tss2.bin of size 100MB
    Then lidi-file-receive file tss2.bin in 30 seconds
    And the sender Prometheus gauge lidi_send_queue_len is less than or equal to 0

  Scenario: T-SS3 - Transfer succeeds with default configuration on fast loopback
    Given lidi is started with max throughput of 100mbit
    When lidi-file-send file tss3.bin of size 10MB
    Then lidi-file-receive file tss3.bin in 15 seconds


  # ============================================================================
  # SEND PIPELINE BACKPRESSURE TEST — T-SS4
  # ============================================================================

  Scenario: T-SS4 - to_udp backpressure prevents memory growth when UDP worker is slow
    # to_udp is crossbeam_channel::bounded(ports.len()) = bounded(1) by default (lib.rs:204).
    # Unlike the receive pipeline queues which are unbounded, to_udp is already bounded.
    # When send_5000 is starved, client threads block on to_udp.send() after 1 item,
    # backpressure propagates to TCP, and lidi-send RSS stays flat.
    # This test verifies the bounded queue correctly prevents unbounded memory growth.
    Given lidi is started with max throughput of 100mbit
    When lidi-file-send starts sending file tss4.bin of size 100MB
    And wait 2 seconds
    And lidi-send send_5000 thread is paused for 5 seconds
    Then sender memory did not grow by more than 5 MB during thread pause


