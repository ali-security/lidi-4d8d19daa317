# Required Cargo features:
#   lidi-send:    command-line, from-tcp, send-mmsg
#   lidi-receive: command-line, to-tcp, receive-mmsg
#   lidi-clients: tcp
#
# "Send a file with hash enabled" additionally requires:
#   lidi-send:    hash
#   lidi-receive: hash
#   lidi-clients: hash
#
Feature: File transfer edge cases

  Scenario: Send an empty file (0 bytes)
    Given lidi is started
    When lidi-file-send file empty.txt of size 0B
    Then lidi-file-receive file empty.txt in 5 seconds

  Scenario: Send a file with spaces in the name
    Given lidi is started
    When lidi-file-send file "my test file.txt" of size 10KB
    Then lidi-file-receive file "my test file.txt" in 5 seconds

  Scenario: Send a file with hash enabled
    Given lidi is started
    When lidi-file-send file A of size 10KB with hash
    Then lidi-file-receive file A in 5 seconds
    And the hash is logged for file A

  Scenario: lidi-file-receive not started - sender does not crash
    Given lidi-send is started
    When lidi-file-send file A of size 10KB without receiver
    Then lidi-send is still running
