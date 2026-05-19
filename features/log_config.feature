Feature: Test --log-config option with various configurations

  Scenario: Send file without --log-config (use log-level default)
    Given lidi is started
    And logging configuration is disabled
    When lidi-file-send file test.bin of size 1MB
    Then lidi-file-receive file test.bin in 10 seconds

  Scenario: Send file with log-level Debug instead of config file
    Given lidi is started
    And logging configuration is disabled
    And log level is set to Debug
    When lidi-file-send file test.bin of size 1MB
    Then lidi-file-receive file test.bin in 10 seconds

  Scenario: Send file with log-level Off (no logs)
    Given lidi is started
    And logging configuration is disabled
    And log level is set to Off
    When lidi-file-send file test.bin of size 1MB
    Then lidi-file-receive file test.bin in 10 seconds

  Scenario: Non-existent log config file should fail
    Given lidi-send is started
    When lidi-file-send with log-config /nonexistent/path.yaml file test.bin of size 1KB
    Then command should have failed with non-zero exit code

  Scenario: Invalid log config file should fail
    Given lidi-send is started
    And an invalid log4rs config file is created
    When lidi-file-send with the invalid log-config file test.bin of size 1KB
    Then command should have failed with non-zero exit code
