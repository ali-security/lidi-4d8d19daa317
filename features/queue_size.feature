Feature: Queue size management (buffer overflow protection)

  Scenario: queue_size configured to reasonable value handles transfer (T9.7)
    Given queue_size is configured to 64
    And lidi is started with max throughput of 100mbit
    When lidi-file-send file queue_size_test_1.bin of size 2MB
    Then lidi-file-receive file queue_size_test_1.bin in 10 seconds

  Scenario: queue_size configured to very small value handles transfer (T9.7)
    Given queue_size is configured to 4
    And lidi is started with max throughput of 100mbit
    When lidi-file-send file queue_size_test_2.bin of size 500KB
    Then lidi-file-receive file queue_size_test_2.bin in 10 seconds
