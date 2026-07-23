.. _Sending UDP with Lidi:

Sending UDP with Lidi
=====================

``lidi-udp-send`` and ``lidi-udp-receive`` form a tunnel that forwards UDP
datagrams through the lidi diode.  Each datagram is encapsulated with an
8-byte size header on the TCP stream so that the receiver can reconstruct
exact datagram boundaries.

.. code-block:: none

   Send UDP datagrams to lidi-udp-receive.

   Usage: lidi-udp-send [OPTIONS] --from <ip:port> <--to-tcp <ip:port>|--to-unix <path>>

   Options:
         --log-level <Off|Error|Warn|Info|Debug|Trace>  Log level [default: Info]
         --to-tcp <ip:port>                             TCP address and port to connect to lidi-send
         --to-unix <path>                               Path to Unix socket to connect to lidi-send
         --from <ip:port>                               IP address and port to receive UDP packets
     -h, --help                                         Print help

.. code-block:: none

   Receive UDP packets sent by lidi-udp-send.

   Usage: lidi-udp-receive [OPTIONS] --to-bind <ip:port> --to <ip:port> <--from-tcp <ip:port>|--from-unix <path>>

   Options:
         --log-level <Off|Error|Warn|Info|Debug|Trace>
             Log level [default: Info]
         --from-tcp <ip:port>
             IP address and port to accept TCP connections from lidi-receive
         --from-unix <path>
             Path of Unix socket to accept Unix connections from lidi-receive
         --to-bind <ip:port>
             IP address and port to send UDP packets from
         --to <ip:port>
             IP address and port to send UDP packets to
     -h, --help
             Print help

Required ``flush=true`` configuration
--------------------------------------

Unlike file or stream transfers, the UDP tunnel keeps both TCP connections
open for the entire lifetime of the session — ``lidi-udp-send`` never closes
its connection to ``lidi-send``, and ``lidi-receive`` never closes its
connection to ``lidi-udp-receive``.  This means lidi never receives an EOF
that would normally trigger flushing of pending data.  Without explicit
``flush=true`` on both endpoints, datagrams accumulate silently and are never
forwarded.

**lidi-send ``from`` endpoint — mandatory ``flush=true``**

``lidi-send`` fills a RaptorQ block (``block`` bytes, default 220 000) before
encoding and sending it.  If datagrams are smaller than ``block``, the block
is never full and no data is ever sent.  Setting ``flush=true`` tells
``lidi-send`` to encode and send a block after every ``read()`` call,
regardless of how full it is:

.. code-block:: toml

   # lidi-send configuration
   [send]
   from = [ "tcp[flush=true]:127.0.0.1:4000" ]

**lidi-receive ``to`` endpoint — mandatory ``flush=true``**

``lidi-receive`` writes decoded data to ``lidi-udp-receive`` through a
buffered writer.  Without ``flush=true``, the buffer is only flushed when an
``End`` block arrives (i.e. when the sender closes the connection), which
never happens with the UDP tunnel.  Setting ``flush=true`` forces a flush
after each write:

.. code-block:: toml

   # lidi-receive configuration
   [receive]
   to = [ "tcp[flush=true]:127.0.0.1:6000" ]

Minimal example configuration
------------------------------

.. code-block:: toml

   # lidi-send.toml
   ports = [5000]

   [send]
   from = [ "tcp[flush=true]:127.0.0.1:4000" ]   # lidi-udp-send connects here
   to   = "192.168.1.2"

.. code-block:: toml

   # lidi-receive.toml
   ports = [5000]

   [receive]
   from = "0.0.0.0"
   to   = [ "tcp[flush=true]:127.0.0.1:6000" ]   # lidi-udp-receive listens here

Start the components in this order:

.. code-block:: bash

   lidi-receive lidi-receive.toml &
   lidi-send    lidi-send.toml    &

   lidi-udp-receive --from-tcp 127.0.0.1:6000 --to-bind 127.0.0.1:0 --to 127.0.0.1:7000 &
   lidi-udp-send    --to-tcp   127.0.0.1:4000 --from 127.0.0.1:5010
