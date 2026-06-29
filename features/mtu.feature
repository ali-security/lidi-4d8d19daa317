# Required Cargo features:
#   lidi-send:    command-line, from-tcp, send-mmsg
#   lidi-receive: command-line, to-tcp, receive-mmsg
#   lidi-clients: tcp
#
Feature: Send simple files with limited network bandwidth

  Scenario: Send 10MB file with MTU 9000
    # File size only needs to cover several RaptorQ blocks to exercise the MTU 9000
    # path; 10MB (~45 blocks) is sufficient. 400mbit keeps the transfer under 1s.
    Given lidi is started with max throughput of 400mbit and MTU 9000
    When lidi-file-send file A of size 10MB
    Then lidi-file-receive file A in 5 seconds

  Scenario: Send multiple 10MB file with MTU 9000, 3 files received
    Given lidi is started with max throughput of 400mbit and MTU 9000
    When lidi-file-send file A of size 10MB
    And lidi-file-send file B of size 10MB
    And lidi-file-send file C of size 10MB
    Then lidi-file-receive file A in 5 seconds
    And lidi-file-receive file B in 5 seconds
    And lidi-file-receive file C in 5 seconds

