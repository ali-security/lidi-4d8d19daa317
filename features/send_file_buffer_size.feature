# Required Cargo features:
#   lidi-send:    command-line, from-tcp, send-mmsg
#   lidi-receive: command-line, to-tcp, receive-mmsg
#   lidi-clients: tcp
#
Feature: Test --buffer-size option with various values

  Scenario Outline: Send file with different buffer sizes
    Given lidi is started with max throughput of 100mbit
    And buffer size is set to <buffer_size>
    When lidi-file-send file test.bin of size 1MB
    Then lidi-file-receive file test.bin in 10 seconds

    Examples:
      | buffer_size |
      | 512         |
      | 8192        |
      | 65536       |
      | 4194304     |
      | 67108864    |

  Scenario: Buffer size zero should fail
    Given lidi-send is started
    And buffer size is set to 0
    When lidi-file-send file test.bin of size 1KB without receiver
    Then command should have failed with non-zero exit code
