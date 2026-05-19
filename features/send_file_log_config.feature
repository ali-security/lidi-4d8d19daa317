Feature: Test --log-config option with lidi-file-send logging

  Scenario: Send file without --log-config (use log-level default)
    Given logging configuration is disabled
    And lidi is started
    When lidi-file-send file test.bin of size 1MB
    Then lidi-file-receive file test.bin in 10 seconds

  Scenario: Verify lidi-file-send logs at Info level contain only Info and higher priority
    Given a log file is prepared for lidi-file-send with Info level
    And lidi-file-send is configured with Info level logging
    When lidi is started with the configured logging
    And lidi-file-send file test.bin of size 100KB
    Then lidi-file-receive file test.bin in 10 seconds
    And the lidi-file-send log file contains log entries
    And the lidi-file-send log file contains no TRACE level messages
    And the lidi-file-send log file contains no DEBUG level messages

  Scenario: Verify lidi-file-send logs at Debug level contain Debug messages
    Given a log file is prepared for lidi-file-send with Debug level
    And lidi-file-send is configured with Debug level logging
    When lidi is started with the configured logging
    And lidi-file-send file test.bin of size 100KB
    Then lidi-file-receive file test.bin in 10 seconds
    And the lidi-file-send log file contains log entries
    And the lidi-file-send log file contains DEBUG or higher level messages

  Scenario: Verify lidi-file-send logs at Warn level exclude Info and Debug
    Given a log file is prepared for lidi-file-send with Warn level
    And lidi-file-send is configured with Warn level logging
    When lidi is started with the configured logging
    And lidi-file-send file test.bin of size 100KB
    Then lidi-file-receive file test.bin in 10 seconds
    And the lidi-file-send log file contains log entries or is empty
    And the lidi-file-send log file contains no INFO level messages
    And the lidi-file-send log file contains no DEBUG level messages

  Scenario: Verify lidi-file-send logs at Off level produces no logs
    Given a log file is prepared for lidi-file-send with Off level
    And lidi-file-send is configured with Off level logging
    When lidi is started with the configured logging
    And lidi-file-send file test.bin of size 100KB
    Then lidi-file-receive file test.bin in 10 seconds
    And the lidi-file-send log file should be empty

  Scenario: Non-existent log config file should fail
    Given lidi-send is started
    When lidi-file-send with log-config /nonexistent/path.yaml file test.bin of size 1KB
    Then command should have failed with non-zero exit code

  Scenario: Invalid log config file should fail
    Given lidi-send is started
    And an invalid log4rs config file is created
    When lidi-file-send with the invalid log-config file test.bin of size 1KB
    Then command should have failed with non-zero exit code
