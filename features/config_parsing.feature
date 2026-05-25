# Required Cargo features:
#   lidi-send:    command-line, from-tcp
#   lidi-receive: command-line, to-tcp
#
# These tests only verify binary startup and config parsing — no file transfer
# occurs, so tcp (lidi-clients), send-mmsg, and receive-mmsg are not required.
# Scenarios testing lidi-send need from-tcp; those testing lidi-receive need to-tcp.
#
Feature: Configuration parsing (TOML, CLI, defaults, error handling)

  Scenario: Full configuration via TOML file (no CLI overrides)
    Given a TOML config file is created with the following content
      """
      mtu = 9000
      ports = [5000]
      block = 100000
      repair = 2
      max_clients = 4
      heartbeat = 10

      [send]
      log = "INFO"
      to = "127.0.0.1"
      to_bind = "0.0.0.0:0"
      from = ["tcp:127.0.0.1:4000"]

      [receive]
      log = "INFO"
      from = "127.0.0.1"
      to = ["tcp:127.0.0.1:5000"]
      reset_timeout = 3
      """
    When lidi-send is started with this TOML config
    Then lidi-send startup succeeds


  Scenario: CLI option overrides TOML value
    Given a TOML config file is created with
      """
      mtu = 1500
      block = 220000
      repair = 1
      max_clients = 2
      heartbeat = 5

      [send]
      log = "INFO"
      to = "127.0.0.1"
      to_bind = "0.0.0.0:0"
      from = ["tcp:127.0.0.1:4000"]
      """
    When lidi-send is started with "--mtu 9000" flag overriding the config
    Then lidi-send startup succeeds


  Scenario: Malformed TOML produces a clear error
    Given a TOML config file is created with
      """
      mtu = 1500
      ports = [5000  # missing closing bracket
      block = 220000

      [send]
      to = "127.0.0.1"
      """
    When lidi-send is started with this TOML config
    Then lidi-send startup fails
    And the error message contains "TOML" or "parse" or "syntax"


  Scenario: Unknown field in TOML is rejected
    Given a TOML config file is created with
      """
      mtu = 1500
      ports = [5000]
      block = 220000
      unknown_field = "this should not be here"
      repair = 1
      max_clients = 2
      heartbeat = 5

      [send]
      log = "INFO"
      to = "127.0.0.1"
      from = ["tcp:127.0.0.1:4000"]
      """
    When lidi-send is started with this TOML config
    Then lidi-send startup fails
    And the error message contains "unknown" or "unexpected" or "field"


  Scenario: Default values are applied when nothing is configured
    Given a minimal TOML config file is created with
      """
      [send]
      to = "127.0.0.1"
      from = ["tcp:127.0.0.1:4000"]
      """
    When lidi-send is started with this TOML config
    Then lidi-send startup succeeds


  Scenario: Multiple `from` endpoints in TOML configuration
    Given a TOML config file is created with
      """
      mtu = 1500
      ports = [5000]
      block = 220000
      repair = 1
      max_clients = 4
      heartbeat = 5

      [send]
      log = "INFO"
      to = "127.0.0.1"
      to_bind = "0.0.0.0:0"
      from = ["tcp:127.0.0.1:4000", "tcp:127.0.0.1:4001", "tcp:127.0.0.1:4002"]
      """
    When lidi-send is started with this TOML config
    Then lidi-send startup succeeds


  Scenario: Negative repair percentage is rejected
    Given a TOML config file is created with
      """
      mtu = 1500
      ports = [5000]
      repair = -1

      [send]
      to = "127.0.0.1"
      from = ["tcp:127.0.0.1:4000"]
      """
    When lidi-send is started with this TOML config
    Then lidi-send startup fails
    And the error message contains "invalid" or "repair" or "u8"

  Scenario: Missing `from` endpoint is rejected (T14.7a)
    # Tests that at least one 'from' endpoint must be configured in [send] section
    Given a TOML config file is created with
      """
      mtu = 1500
      ports = [5000]

      [send]
      log = "INFO"
      to = "127.0.0.1"
      """
    When lidi-send is started with this TOML config
    Then lidi-send startup fails
    And the error message contains "from" or "endpoint" or "required"


  Scenario: Empty endpoints array is rejected (T14.7b)
    # Tests that endpoints array cannot be empty in [send] section
    Given a TOML config file is created with
      """
      mtu = 1500
      ports = [5000]

      [send]
      to = "127.0.0.1"
      from = []
      """
    When lidi-send is started with this TOML config
    Then lidi-send startup fails
    And the error message contains "from" or "endpoint" or "required"


  Scenario: Missing `to` endpoint in receive config is rejected
    # Tests that at least one 'to' endpoint must be configured in [receive] section
    Given a TOML config file is created with
      """
      mtu = 1500
      ports = [5000]

      [receive]
      from = "127.0.0.1"
      """
    When lidi-receive is started with this TOML config
    Then lidi-receive startup fails
    And the error message contains "to" or "endpoint" or "required" (lidi-receive)


  Scenario: Empty `to` endpoints array in receive config is rejected
    # Tests that endpoints array cannot be empty in [receive] section
    Given a TOML config file is created with
      """
      mtu = 1500
      ports = [5000]

      [receive]
      from = "127.0.0.1"
      to = []
      """
    When lidi-receive is started with this TOML config
    Then lidi-receive startup fails
    And the error message contains "to" or "endpoint" or "required" (lidi-receive)


  Scenario: MTU below minimum (1279) is rejected
    # Tests that MTU must be at least 1280 bytes
    Given a TOML config file is created with
      """
      mtu = 1279
      ports = [5000]

      [send]
      to = "127.0.0.1"
      from = ["tcp:127.0.0.1:4000"]
      """
    When lidi-send is started with this TOML config
    Then lidi-send startup fails
    And the error message contains "MTU" or "1280" or "minimum"


  Scenario: MTU at minimum boundary (1280) is accepted
    # Tests that MTU of exactly 1280 bytes is valid
    Given a TOML config file is created with
      """
      mtu = 1280
      ports = [5000]

      [send]
      to = "127.0.0.1"
      from = ["tcp:127.0.0.1:4000"]
      """
    When lidi-send is started with this TOML config
    Then lidi-send startup succeeds


  Scenario: Large MTU (16000) is accepted
    # Tests that large MTU values are accepted if network supports them
    # No upper limit is enforced - leave it to network configuration
    Given a TOML config file is created with
      """
      mtu = 16000
      ports = [5000]

      [send]
      to = "127.0.0.1"
      from = ["tcp:127.0.0.1:4000"]
      """
    When lidi-send is started with this TOML config
    Then lidi-send startup succeeds
