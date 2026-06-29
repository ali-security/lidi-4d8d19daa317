# Required Cargo features:
#   lidi-send:    command-line, from-tcp, send-mmsg
#   lidi-receive: command-line, to-tcp, receive-mmsg
#   lidi-clients: tcp
#
Feature: Send simple files with limited network bandwidth

  Scenario: Send 10MB file with max network of 100 Mb/s
    # Network simulator drops packets above 100Mb/s; lidi runs at 95mbit so the
    # cap is never hit. 10MB at ~12MB/s takes <1s, well within the 5s grace.
    Given there is a limited network bandwidth of 100 Mb/s
    And lidi is started with max throughput of 95mbit
    When lidi-file-send file A of size 10MB
    Then lidi-file-receive file A in 5 seconds

  Scenario: Send multiple 10MB file with max network of 100 Mb/s, 3 files received
    Given there is a limited network bandwidth of 100 Mb/s
    And lidi is started with max throughput of 95mbit
    When lidi-file-send file A of size 10MB
    And lidi-file-send file B of size 10MB
    And lidi-file-send file C of size 10MB
    Then lidi-file-receive file A in 5 seconds
    And lidi-file-receive file B in 5 seconds
    And lidi-file-receive file C in 5 seconds

  Scenario: Ensure bandwidth is never exceeded
    # tc shaper enforces 990kbit at the packet level regardless of file size;
    # 500KB (~4s of data) gives the network simulator a stable measurement window.
    Given network bandwidth must not exceed 1 Mb/s
    And lidi is started with max throughput of 990kbit
    When lidi-file-send file A of size 500KB
    Then lidi-file-receive file A in 10 seconds
