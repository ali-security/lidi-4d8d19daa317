# Required Cargo features:
#   lidi-send:    command-line, from-tcp, send-mmsg
#   lidi-receive: command-line, to-tcp, receive-mmsg
#   lidi-clients: tcp, inotify, log4rs
#
# Both inotify (for --watch) and log4rs must be compiled into lidi-clients.
#
Feature: Test --log-config option with lidi-dir-send logging

  Scenario: Start lidi-dir-send without --log-config (use log-level default)
    Given a log file is prepared for lidi-dir-send with Info level
    When lidi-dir-send is started without log-config
    Then lidi-dir-send should be running

  Scenario: Verify lidi-dir-send logs at Info level contain only Info and higher priority
    Given a log file is prepared for lidi-dir-send with Info level
    And lidi-dir-send is configured with Info level logging
    When lidi-dir-send is started with the configured logging
    Then lidi-dir-send should be running
    And the lidi-dir-send log file contains log entries
    And the lidi-dir-send log file contains no TRACE level messages
    And the lidi-dir-send log file contains no DEBUG level messages

  Scenario: Verify lidi-dir-send logs at Debug level contain Debug messages
    Given a log file is prepared for lidi-dir-send with Debug level
    And lidi-dir-send is configured with Debug level logging
    When lidi-dir-send is started with the configured logging
    Then lidi-dir-send should be running
    And the lidi-dir-send log file contains log entries
    And the lidi-dir-send log file contains DEBUG or higher level messages

  Scenario: Verify lidi-dir-send logs at Warn level exclude Info and Debug
    Given a log file is prepared for lidi-dir-send with Warn level
    And lidi-dir-send is configured with Warn level logging
    When lidi-dir-send is started with the configured logging
    Then lidi-dir-send should be running
    And the lidi-dir-send log file contains log entries or is empty
    And the lidi-dir-send log file contains no INFO level messages
    And the lidi-dir-send log file contains no DEBUG level messages

  Scenario: Verify lidi-dir-send logs at Off level produces no logs
    Given a log file is prepared for lidi-dir-send with Off level
    And lidi-dir-send is configured with Off level logging
    When lidi-dir-send is started with the configured logging
    Then lidi-dir-send should be running
    And wait 2 seconds
    And the lidi-dir-send log file should be empty

  Scenario: Non-existent log config file should fail
    When lidi-dir-send with log-config /nonexistent/path.yaml
    Then command should have failed with non-zero exit code

  Scenario: Invalid log config file should fail
    Given an invalid log4rs config file is created
    When lidi-dir-send with the invalid log-config
    Then command should have failed with non-zero exit code
