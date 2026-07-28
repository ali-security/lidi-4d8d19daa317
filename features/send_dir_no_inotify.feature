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
    And lidi-dir-send is started with non-recursive dynamic watch without inotify
    When we copy a file A of size 1KB
    Then lidi-file-receive file A in 5 seconds

  Scenario: Copy multiple 1K files with lidi-dir-send without inotify
    Given lidi is started with max throughput of 100mbit
    And lidi-dir-send is started with non-recursive dynamic watch without inotify
    When we copy a file A of size 1KB
    When we copy a file B of size 1KB
    When we copy a file C of size 1KB
    Then lidi-file-receive file A in 5 seconds
    Then lidi-file-receive file B in 5 seconds
    Then lidi-file-receive file C in 5 seconds

  Scenario: Move a 1K file with lidi-dir-send without inotify
    Given lidi is started with max throughput of 100mbit
    And lidi-dir-send is started with non-recursive dynamic watch without inotify
    When we move a file A of size 1KB
    Then lidi-file-receive file A in 5 seconds

  Scenario: Move a directory with static lidi-dir-send without inotify
    Given lidi-file-receive uses a temporary directory
    And lidi is started with max throughput of 100mbit
    And lidi-dir-send is started with non-recursive static watch without inotify
    When we move a directory A of size 1MB in the input directory
    Then lidi-file-receive dir A in 5 seconds

  Scenario: Move a directory with dynamic lidi-dir-send without inotify
    # In dynamic mode, new directories should be watched instead of sent. 
    # Consequently, only files are transferred, so empty dirs should not
    # be created receiver side.
    # The scenario creates a directory hierarchy sender side, as follows:
    #    DIR
    #    ├── .A        (dir)
    #    │   └── AA    (file)
    #    ├── B         (dir)
    #    │   └── BB    (dir)
    #    └── .C        (file)
    # Receiver side, the empty dir should not have been transferred:
    #    DIR
    #    ├── .A        (dir)
    #    │   └── AA    (file)
    #    └── .C        (file)
    Given lidi-file-receive uses a temporary directory
    And lidi is started with max throughput of 100mbit
    And lidi-dir-send is started with recursive dynamic watch without inotify
    When we move a directory DIR of size 1MB in the input directory
    Then lidi-file-receive file DIR/.A/AA in 5 seconds
    And lidi-file-receive file DIR/.C in 5 seconds
    And lidi-file-receive no dir DIR/B in 2 seconds

  Scenario: Move a directory inside a directory with recursive lidi-dir-send without inotify
    # In static mode, new directories are sent instead of watched.
    # This test creates a directory "DIR" before, and another one "A" after
    # the start of lidi-dir-send.
    # "DIR" should be watched, and "A" should be sent.
    Given lidi-file-receive uses a temporary directory
    And an empty directory DIR exists in the input directory
    And lidi is started with max throughput of 100mbit
    And lidi-dir-send is started with recursive static watch without inotify
    When we move a directory DIR/A of size 1MB in the input directory
    Then lidi-file-receive dir DIR/A in 5 seconds

  Scenario: Move a directory inside a directory with non-recursive lidi-dir-send without inotify
    # In non-recursive mode, sub-directories are not watched. Nothing should be sent.
    Given lidi-file-receive uses a temporary directory
    And an empty directory DIR exists in the input directory
    And lidi is started with max throughput of 100mbit
    And lidi-dir-send is started with non-recursive static watch without inotify
    When we move a directory DIR/A of size 1MB in the input directory
    Then lidi-file-receive no dir DIR/A in 2 seconds
