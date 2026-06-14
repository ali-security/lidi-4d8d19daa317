# Required Cargo features:
#   lidi-send:    command-line, from-tcp, send-mmsg, prometheus
#   lidi-receive: command-line, to-tcp, receive-mmsg, prometheus
#   lidi-clients: tcp
#
Feature: Prometheus metrics (lidi-send / lidi-receive)

  Prometheus metrics expose the internal state and performance of lidi
  via an HTTP endpoint (configured on 9001/9002).

  Metrics collected:
    - Sender: lidi_send_udp_packets (counter), lidi_send_queue_len (gauge)
    - Receiver: lidi_receive_blocks_decoded (counter), lidi_receive_blocks_lost (counter),
      lidi_receive_decode_with_n_packets (histogram)

  Scenario: Prometheus HTTP endpoint is reachable (T15.1)
    Given lidi is started with max throughput of 90mbit
    When lidi-file-send file A of size 1MB
    Then lidi-file-receive file A in 10 seconds
    And the Prometheus endpoint on 9001 responds with metrics
    And the Prometheus endpoint on 9002 responds with metrics

  Scenario: lidi_send_udp_packets counter incremented (T15.2)
    Given lidi is started with max throughput of 90mbit
    When lidi-file-send file A of size 100KB
    Then lidi-file-receive file A in 10 seconds
    And the sender Prometheus counter lidi_send_udp_packets is greater than 1

  Scenario: lidi_receive_blocks_decoded counter incremented (T15.4)
    Given lidi is started with max throughput of 90mbit
    When lidi-file-send file A of size 100KB
    Then lidi-file-receive file A in 10 seconds
    And the receiver Prometheus counter lidi_receive_blocks_decoded is greater than 1

  Scenario: lidi_receive_blocks_lost incremented with network loss (T15.5)
    Given there is a network interrupt of 100KB after 50KB
    And there is a limited network bandwidth of 100 Mb/s
    And lidi is started with max throughput of 90mbit
    When lidi-file-send file A of size 100KB
    And lidi-file-send file B of size 100KB
    And lidi-file-send file C of size 100KB
    Then lidi-file-receive file C in 5 seconds
    And the receiver Prometheus counter lidi_receive_blocks_lost is greater than 1

  Scenario: Prometheus metrics available during transfer (T15.6)
    Given lidi is started with max throughput of 90mbit
    When lidi-file-send file A of size 500KB
    Then lidi-file-receive file A in 15 seconds
    And the Prometheus endpoint on 9001 responds with metrics
    And the Prometheus endpoint on 9002 responds with metrics

  Scenario: lidi_send_queue_len gauge is available (T15.7)
    Given lidi is started with max throughput of 90mbit
    When lidi-file-send file A of size 100KB
    Then lidi-file-receive file A in 10 seconds
    And the sender Prometheus gauge lidi_send_queue_len is greater than or equal to 0

  Scenario: lidi_send_block_recycler_len gauge is available (T15.8)
    Given lidi is started with max throughput of 90mbit
    When lidi-file-send file A of size 100KB
    Then lidi-file-receive file A in 10 seconds
    And the sender Prometheus gauge lidi_send_block_recycler_len is greater than or equal to 0

  Scenario: lidi_receive_blocks_reassembled counter incremented (T15.9)
    Given lidi is started with max throughput of 90mbit
    When lidi-file-send file A of size 500KB
    Then lidi-file-receive file A in 10 seconds
    And the receiver Prometheus counter lidi_receive_blocks_reassembled is greater than 1

  Scenario: lidi_receive_packets_ignored counter with packet loss (T15.10)
    Given lidi is started with max throughput of 500kbit
    And network packet loss rate is 10%
    When lidi-file-send file A of size 100KB
    Then lidi-file-receive file A in 30 seconds
    And the receiver Prometheus counter lidi_receive_packets_ignored is greater than or equal to 1

  Scenario: lidi_receive_reblock_queue_len gauge available (T15.11)
    Given lidi is started with max throughput of 90mbit
    When lidi-file-send file A of size 100KB
    Then lidi-file-receive file A in 10 seconds
    And the receiver Prometheus gauge lidi_receive_reblock_queue_len is greater than or equal to 0

  Scenario: lidi_receive_dispatch_queue_len gauge available (T15.13)
    Given lidi is started with max throughput of 90mbit
    When lidi-file-send file A of size 500KB
    Then lidi-file-receive file A in 10 seconds
    And the receiver Prometheus gauge lidi_receive_dispatch_queue_len is greater than or equal to 0

  Scenario: lidi_receive_decode_with_n_packets histogram present (T15.14)
    Given lidi is started with max throughput of 90mbit
    When lidi-file-send file A of size 100KB
    Then lidi-file-receive file A in 10 seconds
    And the receiver Prometheus histogram lidi_receive_decode_with_n_packets has count and sum

  Scenario: lidi_receive_clients_queue_len gauge available (T15.13)
    Given lidi is started with max throughput of 90mbit
    When lidi-file-send file A of size 500KB
    Then lidi-file-receive file A in 10 seconds
    And the receiver Prometheus gauge lidi_receive_clients_queue_len is greater than or equal to 0

  Scenario: lidi_receive_client_sendq_total_len gauge available (T15.15)
    Given lidi is started with max throughput of 90mbit
    When lidi-file-send file A of size 500KB
    Then lidi-file-receive file A in 10 seconds
    And the receiver Prometheus gauge lidi_receive_client_sendq_total_len is greater than or equal to 0

  Scenario: lidi_receive_client_sendq_max_len gauge available (T15.16)
    Given lidi is started with max throughput of 90mbit
    When lidi-file-send file A of size 500KB
    Then lidi-file-receive file A in 10 seconds
    And the receiver Prometheus gauge lidi_receive_client_sendq_max_len is greater than or equal to 0
