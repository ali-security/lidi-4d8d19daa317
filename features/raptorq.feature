# Required Cargo features:
#   lidi-send:    command-line, from-tcp, send-mmsg
#   lidi-receive: command-line, to-tcp, receive-mmsg  (phase 3 only)
#   lidi-clients: tcp                                 (phase 3 only)
#
# Phases 1-2 only start lidi-send; phase 3 runs the full stack.
#
Feature: RaptorQ parameter validation: log, packet capture, and end-to-end transfer

  Combined three-level verification for each parameter set:
    1. Log check    — lidi-send startup log reports correct encoded block size
                      and packet counts (symbol_count + repair packets)
    2. Packet capture — actual UDP packets counted and payload size measured
                        using a Python UDP socket on port 5000
    3. End-to-end   — complete file transfer through the full diode stack
                      (lidi-file-send -> lidi-send -> lidi-receive -> lidi-file-receive)

  Phases 1 and 2 run with lidi-send alone (UDP counter on port 5000).
  A transition step stops the counter, kills lidi-send, then restarts the
  full diode for phase 3.

  Repair baseline is 25% (realistic for diode deployments).
  Repair percentage variations show the effect on packet count.

  Encoding formulas (lidi-protocol/src/lib.rs):
    max_packet_size = floor((mtu - 32) / 8) * 8
    symbol_count    = block_size // max_packet_size
    transfer_length = max_packet_size * symbol_count
    min_packets     = symbol_count + 2
    extra_repair    = ceil((min_packets * r) / (1 - r))   r = repair / 100
    nb_packets      = symbol_count + 2 + extra_repair
    udp_payload     = max_packet_size + 4  (RaptorQ header)

  Sending (transfer_length - 12) bytes via TCP keeps the payload one byte
  below the block capacity (max_data_len = transfer_length - SERIALIZE_OVERHEAD,
  with SERIALIZE_OVERHEAD = 11; the sender flushes a Data block as soon as
  cursor >= max_data_len, so the payload must stay strictly below it),
  avoiding an extra full Data block.  This
  produces exactly 2 blocks (Start + End), hence 2 * nb_packets UDP packets.

  Scenario Outline: RaptorQ parameters: log, capture, and file transfer
    # --- Phase 1 & 2: lidi-send alone + UDP counter ---
    Given a UDP packet counter is listening on port 5000
    And heartbeat is disabled
    And lidi-send is configured with MTU <mtu>, block size <block_size> and repair <repair>%
    And lidi-send is started with max throughput of 100mbit
    Then lidi-send reports encoded block <transfer_length> bytes, <min_packets> base packets and <extra_repair> extra repair packets
    When a TCP client sends <data_bytes> bytes to lidi-send and disconnects
    Then the UDP packet counter receives <total_packets> packets
    And each UDP packet payload is <udp_payload> bytes
    # --- Phase 3: full end-to-end transfer ---
    When lidi-receive is added to complete the diode
    And lidi-file-send file A of size 1MB
    Then lidi-file-receive file A in 10 seconds

    Examples: MTU variations (block=220000, repair=25%)
      | mtu  | block_size | repair | transfer_length | min_packets | extra_repair | data_bytes | total_packets | udp_payload |
      | 1280 | 220000     | 25     | 219648          | 178         | 60           | 219636     | 476           | 1252        |
      | 1500 | 220000     | 25     | 219600          | 152         | 51           | 219588     | 406           | 1468        |
      | 9000 | 220000     | 25     | 215232          | 26          | 9            | 215220     | 70            | 8972        |

    Examples: Block size variations (mtu=1500, repair=25%)
      | mtu  | block_size | repair | transfer_length | min_packets | extra_repair | data_bytes | total_packets | udp_payload |
      | 1500 | 50000      | 25     | 49776           | 36          | 12           | 49764      | 96            | 1468        |
      | 1500 | 440000     | 25     | 439200          | 302         | 101          | 439188     | 806           | 1468        |

    Examples: Repair percentage variations (mtu=1500, block=220000)
      | mtu  | block_size | repair | transfer_length | min_packets | extra_repair | data_bytes | total_packets | udp_payload |
      | 1500 | 220000     | 0      | 219600          | 152         | 0            | 219588     | 304           | 1468        |
      | 1500 | 220000     | 10     | 219600          | 152         | 17           | 219588     | 338           | 1468        |
      | 1500 | 220000     | 50     | 219600          | 152         | 152          | 219588     | 608           | 1468        |
