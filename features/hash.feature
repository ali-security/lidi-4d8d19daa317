# Required Cargo features:
#   lidi-send:    command-line, from-tcp, send-mmsg, hash
#   lidi-receive: command-line, to-tcp, receive-mmsg, hash
#   lidi-clients: tcp, hash
#
Feature: Data integrity hashing (XXHash3)

  Scenario: Hash enabled on both sides - file received without error (T8.1)
    Given lidi is started with hash on receiver
    When lidi-file-send file hash_test.bin of size 10KB with hash
    Then lidi-file-receive file hash_test.bin in 5 seconds
    And the receiver log contains no hash error

  Scenario: Hash disabled - file transfer succeeds without hash validation (T8.2)
    Given lidi is started
    When lidi-file-send file nohash_test.bin of size 10KB
    Then lidi-file-receive file nohash_test.bin in 5 seconds

  Scenario: Multiple transfers with hash all succeed (T8.3)
    Given lidi is started with hash on receiver
    When lidi-file-send file file1.bin of size 10KB with hash
    And lidi-file-send file file2.bin of size 20KB with hash
    And lidi-file-send file file3.bin of size 5KB with hash
    Then lidi-file-receive file file1.bin in 5 seconds
    And lidi-file-receive file file2.bin in 5 seconds
    And lidi-file-receive file file3.bin in 5 seconds
    And the receiver log contains no hash error

  Scenario: Hash mismatch detected when sender omits hash (T8.4)
    Given lidi is started with hash on receiver
    When lidi-file-send file corrupt_test.bin of size 10KB
    Then the receiver log contains a hash error
