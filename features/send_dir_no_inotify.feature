# Required Cargo features:
#   lidi-send:    command-line, from-tcp, send-mmsg
#   lidi-receive: command-line, to-tcp, receive-mmsg
#   lidi-clients: tcp, hash, log4rs (built without inotify)
#
# These scenarios run lidi-dir-send --watch against a build of lidi-clients
# compiled without the inotify feature, exercising the directory polling
# fallback used to detect new files.
#
Feature: Check lidi-dir-send --watch falls back to polling without inotify

  Scenario: Copy a 1K file with lidi-dir-send without inotify
    Given lidi is started with max throughput of 100mbit
    And lidi-dir-send is started with watch without inotify
    When we copy a file A of size 1KB
    Then lidi-file-receive file A in 5 seconds

  Scenario: Copy multiple 1K files with lidi-dir-send without inotify
    Given lidi is started with max throughput of 100mbit
    And lidi-dir-send is started with watch without inotify
    When we copy a file A of size 1KB
    When we copy a file B of size 1KB
    When we copy a file C of size 1KB
    Then lidi-file-receive file A in 5 seconds
    Then lidi-file-receive file B in 5 seconds
    Then lidi-file-receive file C in 5 seconds

  Scenario: Move a 1K file with lidi-dir-send without inotify
    Given lidi is started with max throughput of 100mbit
    And lidi-dir-send is started with watch without inotify
    When we move a file A of size 1KB
    Then lidi-file-receive file A in 5 seconds
