# Required Cargo features:
#   lidi-send:    command-line, from-tcp, send-mmsg
#   lidi-receive: command-line, to-tcp, receive-mmsg
#   lidi-clients: tcp
#
# The last scenario ("Network blackout causes partial blocks to fail decoding") also requires:
#   lidi-send:    prometheus
#   lidi-receive: prometheus
#
Feature: Send simple files with network interrupts

  Scenario: Send 3x100KB file with network interrupt, 2 first files lost, last one transmitted
    Given there is a network interrupt of 100KB after 50KB
    And there is a limited network bandwidth of 100 Mb/s
    And lidi is started with max throughput of 90mbit
    When lidi-file-send file A of size 100KB
    And lidi-file-send file B of size 100KB
    And lidi-file-send file C of size 100KB
    Then lidi-file-receive file C in 5 seconds

  Scenario: Send 3x1MB file with network interrupt, 2 first files lost, last one transmitted
    Given there is a network interrupt of 1MB after 500KB
    And there is a limited network bandwidth of 100 Mb/s
    And lidi is started with max throughput of 90mbit
    When lidi-file-send file A of size 1MB
    And lidi-file-send file B of size 1MB
    And lidi-file-send file C of size 1MB
    Then lidi-file-receive file C in 5 seconds

  Scenario: Send 3x10MB file with network interrupt, 2 first files lost, last one transmitted
    # 10MB files at 90mbit: 30MB total takes ~2.7s. Interrupt (5-15MB) covers
    # half of A and half of B, leaving C (20-30MB) entirely clean.
    Given there is a network interrupt of 10MB after 5MB
    And there is a limited network bandwidth of 100 Mb/s
    And lidi is started with max throughput of 90mbit
    When lidi-file-send file A of size 10MB
    And lidi-file-send file B of size 10MB
    And lidi-file-send file C of size 10MB
    Then lidi-file-receive file C in 5 seconds

  Scenario: Network timeout during transfer increments blocks_lost metric
    Given there is a network interrupt of 100KB after 50KB
    And there is a limited network bandwidth of 100 Mb/s
    And lidi is started with max throughput of 90mbit
    When lidi-file-send file A of size 100KB
    And lidi-file-send file B of size 100KB
    And lidi-file-send file C of size 100KB
    Then lidi-file-receive file C in 5 seconds
    And the receiver Prometheus counter lidi_receive_blocks_lost is greater than or equal to 1

