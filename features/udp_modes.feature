# Required Cargo features (vary per scenario — see inline comments):
#   lidi-send:    command-line, from-tcp, and one of: send-native, send-msg, send-mmsg
#   lidi-receive: command-line, to-tcp, and one of: receive-native, receive-msg, receive-mmsg
#   lidi-clients: tcp
#
# Each scenario documents the exact send/receive mode it requires in its inline comment.
# Disabling send-native breaks T5.1; send-msg breaks T5.2; receive-native breaks T5.4 and T5.8;
# receive-msg breaks T5.5.
Feature: UDP send/receive modes (native, msg, mmsg)

  # send=native, recv=mmsg (default receive side)
  Scenario: Send mode native transfers a file successfully (T5.1)
    Given UDP send mode is native
    And lidi is started with max throughput of 100mbit
    When lidi-file-send file udp_mode_test_1.bin of size 5MB
    Then lidi-file-receive file udp_mode_test_1.bin in 15 seconds
    And the sender log shows send mode native

  # send=msg, recv=mmsg (default receive side)
  Scenario: Send mode msg transfers a file successfully (T5.2)
    Given UDP send mode is msg
    And lidi is started with max throughput of 100mbit
    When lidi-file-send file udp_mode_test_2.bin of size 5MB
    Then lidi-file-receive file udp_mode_test_2.bin in 15 seconds
    And the sender log shows send mode msg

  # send=mmsg (default send side), recv=native
  Scenario: Receive mode native transfers a file successfully (T5.4)
    Given UDP receive mode is native
    And lidi is started with max throughput of 100mbit
    When lidi-file-send file udp_mode_test_3.bin of size 5MB
    Then lidi-file-receive file udp_mode_test_3.bin in 15 seconds
    And the receiver log shows receive mode native

  # send=mmsg (default send side), recv=msg
  Scenario: Receive mode msg transfers a file successfully (T5.5)
    Given UDP receive mode is msg
    And lidi is started with max throughput of 100mbit
    When lidi-file-send file udp_mode_test_4.bin of size 5MB
    Then lidi-file-receive file udp_mode_test_4.bin in 15 seconds
    And the receiver log shows receive mode msg

  # send=mmsg, recv=native (cross-mode interoperability)
  Scenario: Cross-mode interoperability send-mmsg receive-native (T5.8)
    Given UDP send mode is mmsg
    And UDP receive mode is native
    And lidi is started with max throughput of 100mbit
    When lidi-file-send file udp_mode_test_5.bin of size 5MB
    Then lidi-file-receive file udp_mode_test_5.bin in 15 seconds
    And the sender log shows send mode mmsg
    And the receiver log shows receive mode native
