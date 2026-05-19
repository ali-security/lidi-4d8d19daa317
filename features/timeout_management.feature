Feature: Timeout management (reset_timeout, abort_timeout)

  Scenario: reset_timeout configuration accepted and normal transfer succeeds (T9.1, T9.2, T9.6)
    Given reset_timeout is configured to 1000 milliseconds
    And lidi is started with max throughput of 100mbit
    When lidi-file-send file timeout_test_1.bin of size 5MB
    Then lidi-file-receive file timeout_test_1.bin in 15 seconds

  Scenario: reset_timeout with very short value still works (T9.2)
    Given reset_timeout is configured to 50 milliseconds
    And lidi is started with max throughput of 100mbit
    When lidi-file-send file timeout_test_2.bin of size 2MB
    Then lidi-file-receive file timeout_test_2.bin in 15 seconds

  Scenario: abort_timeout configured does not prevent normal transfer (T9.3)
    Given abort_timeout is configured to 5 seconds
    And lidi is started with max throughput of 100mbit
    When lidi-file-send file timeout_test_3.bin of size 1MB
    Then lidi-file-receive file timeout_test_3.bin in 10 seconds
    And the receiver daemon is still running

  Scenario: abort_timeout disabled still allows transfer (T9.4)
    Given abort_timeout is disabled
    And lidi is started with max throughput of 100mbit
    When lidi-file-send file timeout_test_4.bin of size 1MB
    Then lidi-file-receive file timeout_test_4.bin in 10 seconds
    And the receiver daemon is still running
