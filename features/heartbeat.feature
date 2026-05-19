Feature: Heartbeat mechanism

  Scenario: Missed heartbeat produces a log warning (T6.3)
    Given heartbeat is configured to 1 second
    And there is a network blackout of 2000 milliseconds after 100 milliseconds
    And lidi is started with max throughput of 100kbit
    When lidi-file-send file heartbeat_test.bin of size 100KB
    Then wait 2 seconds
    And the receiver log contains a missed heartbeat warning

  Scenario: No heartbeat warning during normal transfer (with tolerance margin)
    Given heartbeat sender is 1 second and receiver is 1 second
    And lidi is started with max throughput of 100mbit
    When lidi-file-send file normal_transfer.bin of size 5MB
    Then lidi-file-receive file normal_transfer.bin in 30 seconds
    And the receiver log does not contain a missed heartbeat warning
