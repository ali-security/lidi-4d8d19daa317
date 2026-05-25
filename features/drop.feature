# Required Cargo features:
#   lidi-send:    command-line, from-tcp, send-mmsg
#   lidi-receive: command-line, to-tcp, receive-mmsg
#   lidi-clients: tcp
#
# The "Blocks fail to decode when drop rate exceeds repair capacity" scenario
# also requires:
#   lidi-send:    prometheus
#   lidi-receive: prometheus
#
Feature: Send simple files with network drop
  
  Scenario: Send a 100K file with drop
    Given there is a network drop of 5 %
    And repair percentage is 5 %
    And lidi is started with max throughput of 100mbit
    When lidi-file-send file A of size 100KB
    Then lidi-file-receive file A in 5 seconds

  Scenario: Send a 100M file with drop
    Given there is a network drop of 5 %
    And repair percentage is 5 %
    And lidi is started with max throughput of 100mbit
    When lidi-file-send file A of size 100MB 
    Then lidi-file-receive file A in 5 seconds

  Scenario: Send a 10M file with high drop
    Given there is a network drop of 40 %
    And repair percentage is 40 %
    And lidi is started with max throughput of 100mbit
    When lidi-file-send file A of size 10MB
    Then lidi-file-receive file A in 5 seconds

  Scenario: Blocks fail to decode when drop rate exceeds repair capacity
    Given there is a network drop of 50 %
    And repair percentage is 10 %
    And lidi is started with max throughput of 100mbit
    When lidi-file-send file A of size 100KB
    Then wait 10 seconds
    And the receiver Prometheus counter lidi_receive_blocks_decode_failed is greater than or equal to 1
