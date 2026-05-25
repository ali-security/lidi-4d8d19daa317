# Required Cargo features:
#   lidi-receive: command-line, to-tcp, receive-mmsg, log4rs
#
# Only lidi-receive is started in these tests; lidi-send and lidi-clients
# are not involved. The log4rs feature must be compiled into lidi-receive.
#
Feature: Test --log-config option with lidi-receive logging

  Scenario: Start lidi-receive without --log-config (use log-level default)
    Given a log file is prepared for lidi-receive with Info level
    When lidi-receive is started without log-config
    Then lidi-receive should be running

  Scenario: Verify lidi-receive logs at Info level contain only Info and higher priority
    Given a log file is prepared for lidi-receive with Info level
    And lidi-receive is configured with Info level logging
    When lidi-receive is started with the configured logging
    Then lidi-receive should be running
    And the lidi-receive log file contains log entries
    And the lidi-receive log file contains no TRACE level messages
    And the lidi-receive log file contains no DEBUG level messages

  Scenario: Verify lidi-receive logs at Debug level contain Debug messages
    Given a log file is prepared for lidi-receive with Debug level
    And lidi-receive is configured with Debug level logging
    When lidi-receive is started with the configured logging
    Then lidi-receive should be running
    And the lidi-receive log file contains log entries
    And the lidi-receive log file contains DEBUG or higher level messages

  Scenario: Verify lidi-receive logs at Warn level exclude Info and Debug
    Given a log file is prepared for lidi-receive with Warn level
    And lidi-receive is configured with Warn level logging
    When lidi-receive is started with the configured logging
    Then lidi-receive should be running
    And the lidi-receive log file contains log entries or is empty
    And the lidi-receive log file contains no INFO level messages
    And the lidi-receive log file contains no DEBUG level messages

  Scenario: Verify lidi-receive logs at Off level produces no logs
    Given a log file is prepared for lidi-receive with Off level
    And lidi-receive is configured with Off level logging
    When lidi-receive is started with the configured logging
    Then lidi-receive should be running
    And wait 2 seconds
    And the lidi-receive log file should be empty

  Scenario: Non-existent log config file should fail
    When lidi-receive with log-config /nonexistent/path.yaml
    Then command should have failed with non-zero exit code

  Scenario: Invalid log config file should fail
    Given an invalid log4rs config file is created
    When lidi-receive with the invalid log-config
    Then command should have failed with non-zero exit code
