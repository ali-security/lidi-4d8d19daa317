# Required Cargo features:
#   lidi-send:    command-line, from-tcp, send-mmsg
#   lidi-receive: command-line, to-tcp, receive-mmsg
#   lidi-clients: tcp, log4rs
#
# The log4rs feature must be compiled into lidi-clients (lidi-file-receive binary).
# The first scenario starts lidi-file-receive standalone (needs tcp, log4rs in clients);
# other scenarios run the full stack.
#
Feature: Test --log-config option with lidi-file-receive logging

  Scenario: Start lidi-file-receive without --log-config (use log-level default)
    Given a log file is prepared for lidi-file-receive with Info level
    When lidi-file-receive is started without log-config
    Then lidi-file-receive should be running

  Scenario: Verify lidi-file-receive logs at Info level contain only Info and higher priority
    Given a log file is prepared for lidi-file-receive with Info level
    And lidi-file-receive is configured with Info level logging
    When lidi-file-receive is started with the configured logging
    Then lidi-file-receive should be running
    And the lidi-file-receive log file contains log entries
    And the lidi-file-receive log file contains no TRACE level messages
    And the lidi-file-receive log file contains no DEBUG level messages

  Scenario: Verify lidi-file-receive logs at Debug level contain Debug messages
    Given a log file is prepared for lidi-file-receive with Debug level
    And lidi-file-receive is configured with Debug level logging
    When lidi-file-receive is started with the configured logging
    Then lidi-file-receive should be running
    And the lidi-file-receive log file contains log entries
    And the lidi-file-receive log file contains DEBUG or higher level messages

  Scenario: Verify lidi-file-receive logs at Warn level exclude Info and Debug
    Given a log file is prepared for lidi-file-receive with Warn level
    And lidi-file-receive is configured with Warn level logging
    When lidi-file-receive is started with the configured logging
    Then lidi-file-receive should be running
    And the lidi-file-receive log file contains log entries or is empty
    And the lidi-file-receive log file contains no INFO level messages
    And the lidi-file-receive log file contains no DEBUG level messages

  Scenario: Verify lidi-file-receive logs at Off level produces no logs
    Given a log file is prepared for lidi-file-receive with Off level
    And lidi-file-receive is configured with Off level logging
    When lidi-file-receive is started with the configured logging
    Then lidi-file-receive should be running
    And wait 2 seconds
    And the lidi-file-receive log file should be empty

  Scenario: Non-existent log config file should fail
    When lidi-file-receive with log-config /nonexistent/path.yaml
    Then command should have failed with non-zero exit code

  Scenario: Invalid log config file should fail
    Given an invalid log4rs config file is created
    When lidi-file-receive with the invalid log-config
    Then command should have failed with non-zero exit code
