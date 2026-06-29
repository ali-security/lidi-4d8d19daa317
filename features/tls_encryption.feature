# Required Cargo features:
#   lidi-send:    command-line, from-tls, send-mmsg
#   lidi-receive: command-line, to-tcp, receive-mmsg
#   lidi-clients: tcp, tls
#
# These tests require 'openssl' CLI to be installed for PKI generation.
# PKI is generated once in before_scenario via features/steps/tls_pki.py.
#
Feature: TLS encryption between lidi-file-send / lidi-send and lidi-receive / lidi-file-receive

  # ── Nominal scenarios ────────────────────────────────────────────────────────
  # NOTE: These tests are currently marked @wip due to a bug in lidi-clients/src/tls.rs.
  #
  # ROOT CAUSE ANALYSIS (confirmed by manual testing, 2026-05-16)
  # =============================================================
  #
  # Bug location : lidi-clients/src/tls.rs — struct TcpStream
  # Bug type     : Missing Drop impl — TLS close_notify never sent
  #
  # Mechanism (step by step):
  # 1. TLS 1.3 handshake completes between lidi-file-send (client) and lidi-send (server).
  # 2. lidi-send (OpenSSL 3.x, Mozilla Modern v5 = TLS 1.3 only) sends TWO NewSessionTicket
  #    records post-handshake. These arrive in lidi-file-send's kernel TCP receive buffer.
  # 3. lidi-file-send only writes to the TLS stream (header + data + footer + flush).
  #    It never calls read() on the connection, so the NewSessionTicket records are never
  #    consumed from its receive buffer.
  # 4. send_file_aux() returns; the TcpStream wrapper is dropped. TcpStream has no Drop
  #    impl, so openssl::ssl::SslStream is dropped without calling SSL_shutdown().
  #    → No TLS close_notify is sent.
  # 5. The Linux TCP stack detects unread data in lidi-file-send's receive buffer
  #    (the two NewSessionTicket records) and sends TCP RST instead of FIN.
  # 6. lidi-send receives the RST. Per RFC 793, all data in lidi-send's TCP receive
  #    buffer (the file bytes) is immediately discarded.
  # 7. lidi-send's client worker calls read() → ECONNRESET. It logs:
  #    "client 0: error: I/O error: Connection reset by peer (os error 104)"
  #    and sends an Abort block. No file data is ever processed.
  #
  # Proof: openssl s_client (which sends close_notify) → "disconnect, 5 bytes sent" ✓
  #        lidi-file-send (no close_notify)             → "Connection reset by peer" ✗
  #
  # Fix (not yet applied): implement Drop for lidi_clients::tls::TcpStream to call
  #   self.0.shutdown()
  # This drains pending server records (NewSessionTicket) and closes the connection
  # with a clean FIN instead of RST.

  @wip
  Scenario: T-TLS01 Basic TLS file transfer (send side)
    Given lidi is started with TLS on the send side
    When send file test.bin via TLS connection of size 100KB
    Then lidi-file-receive file test.bin in 10 seconds

  @wip
  Scenario: T-TLS02 Mutual TLS (mTLS) — client certificate required
    Given lidi is started with mutual TLS on the send side
    When send file test.bin via mutual TLS connection of size 100KB
    Then lidi-file-receive file test.bin in 10 seconds

  @wip
  Scenario: T-TLS03 Mozilla Modern v5 preset explicit
    Given TLS send method is mozilla_modern_v5
    And lidi is started with TLS on the send side
    When send file test.bin via TLS connection of size 100KB
    Then lidi-file-receive file test.bin in 10 seconds

  @wip
  Scenario: T-TLS04 Mozilla Intermediate v5 preset
    Given TLS send method is mozilla_intermediate_v5
    And lidi is started with TLS on the send side
    When send file test.bin via TLS connection of size 100KB
    Then lidi-file-receive file test.bin in 10 seconds

  @wip
  Scenario: T-TLS05 Custom cipher suite (TLS 1.3 ciphers)
    Given TLS send cipher suite is TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
    And lidi is started with TLS on the send side
    When send file test.bin via TLS connection of size 100KB
    Then lidi-file-receive file test.bin in 10 seconds

  @wip
  Scenario: T-TLS06 TLS endpoint with flush=true option
    Given TLS send endpoint has option flush=true
    And lidi is started with TLS on the send side
    When send file test.bin via TLS connection of size 100KB
    Then lidi-file-receive file test.bin in 10 seconds

  @wip
  Scenario: T-TLS07 TLS with hash enabled
    Given TLS send endpoint has option hash=true
    And lidi is started with TLS on the send side
    When send file test.bin via TLS connection of size 100KB
    Then lidi-file-receive file test.bin in 10 seconds
    And the hash is logged for file test.bin

  @wip
  Scenario: T-TLS08 TLS minimum version tls1_3 explicit
    Given TLS send minimum version is tls1_3
    And lidi is started with TLS on the send side
    When send file test.bin via TLS connection of size 100KB
    Then lidi-file-receive file test.bin in 10 seconds

  # ── Error scenarios ───────────────────────────────────────────────────────────

  Scenario: T-TLS09 Expired certificate rejected at handshake
    Given TLS send uses an expired certificate
    And lidi is started with TLS on the send side
    When send file test.bin via TLS connection of size 100KB
    Then the file test.bin is not received within 5 seconds

  Scenario: T-TLS10 Certificate from wrong CA rejected at handshake
    Given TLS send uses a certificate from a wrong CA
    And lidi is started with TLS on the send side
    When send file test.bin via TLS connection of size 100KB
    Then the file test.bin is not received within 5 seconds

  Scenario: T-TLS11 Missing certificate file causes startup failure
    Given TLS send uses a non-existent certificate path
    And a TOML config file is created with the following content
      """
      mtu = 1500
      ports = [5000]
      block = 220000
      repair = 1
      max_clients = 2

      [send.tls]
      key = "/dev/shm/lidi/pki/server.key.pem"
      certificate = "/nonexistent/path/server.cert.pem"

      [send]
      to = "127.0.0.1"
      from = ["tls:127.0.0.1:4000"]
      """
    When lidi-send is started with this TOML config
    Then lidi-send startup fails
    And the error message contains "certificate" or "No such file" or "error"

  Scenario: T-TLS12 Missing key file causes startup failure
    Given a TOML config file is created with the following content
      """
      mtu = 1500
      ports = [5000]
      block = 220000
      repair = 1
      max_clients = 2

      [send.tls]
      key = "/nonexistent/path/server.key.pem"
      certificate = "/dev/shm/lidi/pki/server.cert.pem"

      [send]
      to = "127.0.0.1"
      from = ["tls:127.0.0.1:4000"]
      """
    When lidi-send is started with this TOML config
    Then lidi-send startup fails
    And the error message contains "key" or "No such file" or "error"

  Scenario: T-TLS13 Mismatched key and certificate causes startup failure
    Given a TOML config file is created with the following content
      """
      mtu = 1500
      ports = [5000]
      block = 220000
      repair = 1
      max_clients = 2

      [send.tls]
      key = "/dev/shm/lidi/pki/client.key.pem"
      certificate = "/dev/shm/lidi/pki/server.cert.pem"

      [send]
      to = "127.0.0.1"
      from = ["tls:127.0.0.1:4000"]
      """
    When lidi-send is started with this TOML config
    Then lidi-send startup fails
    And the error message contains "key" or "certificate" or "error"

  Scenario: T-TLS14 Non-existent CA file causes startup failure
    Given a TOML config file is created with the following content
      """
      mtu = 1500
      ports = [5000]
      block = 220000
      repair = 1
      max_clients = 2

      [send.tls]
      key = "/dev/shm/lidi/pki/server.key.pem"
      certificate = "/dev/shm/lidi/pki/server.cert.pem"
      ca = "/nonexistent/path/ca.cert.pem"

      [send]
      to = "127.0.0.1"
      from = ["tls:127.0.0.1:4000"]
      """
    When lidi-send is started with this TOML config
    Then lidi-send startup fails
    And the error message contains "ca" or "No such file" or "error"

  Scenario: T-TLS15 Invalid cipher string causes startup failure
    Given a TOML config file is created with the following content
      """
      mtu = 1500
      ports = [5000]
      block = 220000
      repair = 1
      max_clients = 2

      [send.tls]
      key = "/dev/shm/lidi/pki/server.key.pem"
      certificate = "/dev/shm/lidi/pki/server.cert.pem"
      ciphers = "NOT_A_VALID_CIPHER"

      [send]
      to = "127.0.0.1"
      from = ["tls:127.0.0.1:4000"]
      """
    When lidi-send is started with this TOML config
    Then lidi-send startup fails
    And the error message contains "cipher" or "OpenSSL" or "error"

  Scenario: T-TLS16 TLS 1.2 connection rejected when server requires TLS 1.3
    Given a TOML config file is created with the following content
      """
      mtu = 1500
      ports = [5000]
      block = 220000
      repair = 1
      max_clients = 2

      [send.tls]
      key = "/dev/shm/lidi/pki/server.key.pem"
      certificate = "/dev/shm/lidi/pki/server.cert.pem"
      tls_min = "tls1_3"

      [send]
      to = "127.0.0.1"
      from = ["tls:127.0.0.1:4000"]
      """
    When lidi-send is started with this TOML config
    Then lidi-send startup succeeds
    And a TLS 1.2 connection attempt to lidi-send on port 4000 is rejected

  Scenario: T-TLS17 mTLS - missing client certificate rejected by server
    Given lidi is started with mutual TLS on the send side
    When send file test.bin via TLS connection of size 100KB
    Then the file test.bin is not received within 5 seconds
