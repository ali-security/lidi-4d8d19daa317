# Required Cargo features:
#   lidi-send:    command-line, from-tcp, send-mmsg
#   lidi-receive: command-line, to-tcp, receive-mmsg
#   lidi-clients: tcp, inotify
#
# The inotify feature enables --watch in lidi-dir-send. All scenarios use it.
#
Feature: Check lidi-dir-send is sending one or multiple files with copy or move

  Scenario: Copy a 1K file with lidi-dir-send
    Given lidi is started with max throughput of 100mbit
    And lidi-dir-send is started with non-recursive dynamic watch
    When we copy a file A of size 1KB
    Then lidi-file-receive file A in 5 seconds

  Scenario: Copy multiple 1K files with lidi-dir-send
    Given lidi is started with max throughput of 100mbit
    And lidi-dir-send is started with non-recursive dynamic watch
    When we copy a file A of size 1KB
    When we copy a file B of size 1KB
    When we copy a file C of size 1KB
    Then lidi-file-receive file A in 5 seconds
    Then lidi-file-receive file B in 5 seconds
    Then lidi-file-receive file C in 5 seconds

  Scenario: Move a 1K file with lidi-dir-send
    Given lidi is started with max throughput of 100mbit
    And lidi-dir-send is started with non-recursive dynamic watch
    When we move a file A of size 1KB
    Then lidi-file-receive file A in 5 seconds

  Scenario: Move multiple 1K file with lidi-dir-send
    Given lidi is started with max throughput of 100mbit
    And lidi-dir-send is started with non-recursive dynamic watch
    When we move a file A of size 1KB
    When we move a file B of size 1KB
    When we move a file C of size 1KB
    Then lidi-file-receive file A in 5 seconds
    Then lidi-file-receive file B in 5 seconds
    Then lidi-file-receive file C in 5 seconds

  Scenario: Move a directory with static lidi-dir-send
    Given lidi-file-receive uses a temporary directory
    And lidi is started with max throughput of 100mbit
    And lidi-dir-send is started with non-recursive static watch
    When we move a directory A of size 1MB in the input directory
    Then lidi-file-receive dir A in 5 seconds

  Scenario: Move a directory with dynamic lidi-dir-send
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
    And lidi-dir-send is started with recursive dynamic watch
    When we move a directory DIR of size 1MB in the input directory
    Then lidi-file-receive file DIR/.A/AA in 5 seconds
    And lidi-file-receive file DIR/.C in 5 seconds
    And lidi-file-receive no dir DIR/B in 2 seconds

  Scenario: Move a directory inside a directory with recursive lidi-dir-send
    # In static mode, new directories are sent instead of watched.
    # This test creates a directory "DIR" before, and another one "A" after
    # the start of lidi-dir-send.
    # "DIR" should be watched, and "A" should be sent.
    Given lidi-file-receive uses a temporary directory
    And an empty directory DIR exists in the input directory
    And lidi is started with max throughput of 100mbit
    And lidi-dir-send is started with recursive static watch
    When we move a directory DIR/A of size 1MB in the input directory
    Then lidi-file-receive dir DIR/A in 5 seconds

  Scenario: Move a directory inside a directory with non-recursive lidi-dir-send
    # In non-recursive mode, sub-directories are not watched. Nothing should be sent.
    Given lidi-file-receive uses a temporary directory
    And an empty directory DIR exists in the input directory
    And lidi is started with max throughput of 100mbit
    And lidi-dir-send is started with non-recursive static watch
    When we move a directory DIR/A of size 1MB in the input directory
    Then lidi-file-receive no dir DIR/A in 2 seconds

  Scenario: Send a directory with non-watch non-recursive lidi-dir-send
    # In NON-WATCH NON-RECURSIVE mode, lidi-dir-send should send top-level directories.
    Given lidi-file-receive uses a temporary directory
    And a directory DIR of size 1KB exists in the input directory
    And lidi is started with max throughput of 100mbit
    When lidi-dir-send is started
    Then lidi-file-receive dir DIR in 5 seconds

  Scenario: Send files inside directory with non-watch recursive lidi-dir-send
    # In NON-WATCH RECURSIVE mode, lidi-dir-send should only send files.
    Given lidi-file-receive uses a temporary directory
    And a directory DIR of size 1KB exists in the input directory
    And lidi is started with max throughput of 100mbit
    When lidi-dir-send is started with recursive
    Then lidi-file-receive file DIR/.A/AA in 5 seconds
    And lidi-file-receive file DIR/.C in 5 seconds
    And lidi-file-receive no dir DIR/B in 2 seconds
