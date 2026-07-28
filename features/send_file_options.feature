# Required Cargo features:
#   lidi-send:    command-line, from-tcp, send-mmsg
#   lidi-receive: command-line, to-tcp, receive-mmsg
#   lidi-clients: tcp
#
Feature: Test file management options like --delete and --overwrite

  Scenario: Receive file with the --overwrite argument
    Given lidi-receive-file is configured to overwrite files
    And lidi is started
    When lidi-file-send file A of size 1KB
    When lidi-file-send file A of size 2KB
    Then lidi-file-receive file A in 5 seconds

  Scenario: Send file with the --delete argument
    Given lidi is started
    And lidi-dir-send is started with non-recursive dynamic watch and delete
    When we copy a file A of size 1KB
    Then lidi-file-receive file A in 5 seconds
    And A does not exist in input directory

  Scenario: Send file without the --delete argument
    Given lidi is started
    And lidi-dir-send is started with non-recursive dynamic watch
    When we copy a file A of size 1KB
    Then lidi-file-receive file A in 5 seconds
    And A exists in input directory

  Scenario: Send and receive directory with --overwrite and --delete arguments
    Given lidi-receive-file is configured to overwrite files
    And lidi is started
    And lidi-dir-send is started with non-recursive static watch and delete
    When we move a directory A of size 1KB in the input directory
    And wait 2 seconds
    And we move a directory A of size 2KB in the input directory
    And wait 2 seconds
    Then lidi-file-receive dir A in 5 seconds
    And A does not exist in input directory

  Scenario: Send directory without the --delete argument
    Given lidi is started
    And lidi-dir-send is started with non-recursive static watch
    When we move a directory A of size 1KB in the input directory
    Then lidi-file-receive dir A in 5 seconds
    And A exists in input directory
