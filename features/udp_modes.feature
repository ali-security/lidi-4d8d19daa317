Feature: UDP send/receive modes (native, msg, mmsg)

  Scenario: Send mode native transfers a file successfully (T5.1)
    Given UDP send mode is native
    And lidi is started with max throughput of 100mbit
    When lidi-file-send file udp_mode_test_1.bin of size 5MB
    Then lidi-file-receive file udp_mode_test_1.bin in 15 seconds
    And the sender log shows send mode native

  Scenario: Send mode msg transfers a file successfully (T5.2)
    Given UDP send mode is msg
    And lidi is started with max throughput of 100mbit
    When lidi-file-send file udp_mode_test_2.bin of size 5MB
    Then lidi-file-receive file udp_mode_test_2.bin in 15 seconds
    And the sender log shows send mode msg

  Scenario: Receive mode native transfers a file successfully (T5.4)
    Given UDP receive mode is native
    And lidi is started with max throughput of 100mbit
    When lidi-file-send file udp_mode_test_3.bin of size 5MB
    Then lidi-file-receive file udp_mode_test_3.bin in 15 seconds
    And the receiver log shows receive mode native

  Scenario: Receive mode msg transfers a file successfully (T5.5)
    Given UDP receive mode is msg
    And lidi is started with max throughput of 100mbit
    When lidi-file-send file udp_mode_test_4.bin of size 5MB
    Then lidi-file-receive file udp_mode_test_4.bin in 15 seconds
    And the receiver log shows receive mode msg

  Scenario: Cross-mode interoperability send-mmsg receive-native (T5.8)
    Given UDP send mode is mmsg
    And UDP receive mode is native
    And lidi is started with max throughput of 100mbit
    When lidi-file-send file udp_mode_test_5.bin of size 5MB
    Then lidi-file-receive file udp_mode_test_5.bin in 15 seconds
    And the sender log shows send mode mmsg
    And the receiver log shows receive mode native
