# Required Cargo features:
#   lidi-send:    command-line, from-tcp, send-mmsg
#   lidi-receive: command-line, to-tcp, receive-mmsg
#   lidi-clients: tcp
#
# lidi-udp-send connects to lidi-send via TCP; lidi-receive forwards to
# lidi-udp-receive via TCP. Both tunnel binaries are in lidi-clients.
#
Feature: UDP tunnel (lidi-udp-send / lidi-udp-receive)

  Forward UDP datagrams through the lidi diode, which normally only handles
  TCP/TLS/Unix streams. The tunnel encapsulates each UDP datagram with an
  8-byte size header and reconstructs them on the receive side.

  Topology:
    [UDP Client] → [lidi-udp-send:5010] → [diode] → [lidi-udp-receive] → [UDP Server:5020]

  UDP datagram size limit: 65,535 bytes (OS enforced).

  Scenario: Basic UDP datagram forwarding (T12.1)
    Given lidi diode is started
    And lidi-udp-receive is started forwarding to 5020
    And lidi-udp-send is started listening on 5010
    When a UDP client sends 5 datagrams of 100 bytes each to 5010
    Then the UDP server on 5020 receives exactly 5 datagrams

  Scenario: Datagram size preservation (T12.2)
    Given lidi diode is started
    And lidi-udp-receive is started forwarding to 5020
    And lidi-udp-send is started listening on 5010
    When a UDP client sends datagrams of sizes 64, 256, 1024, 4096, 16384 bytes to 5010
    Then the UDP server on 5020 receives 5 datagrams with matching sizes

  Scenario: High-throughput UDP forwarding (T12.3)
    Given lidi diode is started
    And lidi-udp-receive is started forwarding to 5020
    And lidi-udp-send is started listening on 5010
    When a UDP client sends 100 datagrams of 512 bytes each to 5010 rapidly
    Then the UDP server on 5020 receives at least 95 datagrams in 5 seconds

  Scenario: Oversized datagram handling (T12.4)
    Given lidi diode is started
    And lidi-udp-receive is started forwarding to 5020
    And lidi-udp-send is started listening on 5010
    When a UDP client attempts to send a 100KB datagram to 5010
    Then the datagram is either truncated to 65535 bytes or dropped
    And lidi-udp-send does not crash
