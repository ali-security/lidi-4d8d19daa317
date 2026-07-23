.. _Oneshot Lidi:

Oneshot Lidi
============

The oneshot binaries, ``lidi-send-oneshot`` and ``lidi-receive-oneshot``, are self-contained variants of the diode for transferring a single stream. ``lidi-send-oneshot`` reads its data from standard input and sends it directly through the UDP link, while ``lidi-receive-oneshot`` receives it and writes it to standard output. Unlike ``lidi-send`` / ``lidi-receive``, they do not run TCP/TLS/Unix client listeners, so there is no need to run separate clients (nor ``lidi-send`` / ``lidi-receive``).

They accept the same configuration file and command line options as ``lidi-send`` / ``lidi-receive`` respectively (see :ref:`Command line parameters`), with two differences that are forced internally:

- ``max-clients`` is always ``1`` (a single stream is transferred);
- the heartbeat is always disabled.

The UDP-related parameters (``--to``, ``--to-bind``, ``--from``, ``--ports``, ``--mtu``, ``--block``, ``--repair``, ``--mode``) behave exactly as for the regular binaries and must match on both sides.

Endpoints
---------

- ``lidi-send-oneshot`` always reads from standard input, so no source endpoint (``--from``) is needed.
- ``lidi-receive-oneshot`` always writes to standard output, but it still requires exactly one destination endpoint (``--to``) to be declared. The endpoint is only used so that the incoming transfer is recognized as valid; its declared address is never actually connected to, so any placeholder value works.

Usage
-----

.. code-block:: none

   lidi-send-oneshot    [OPTIONS] [config_file_path]
   lidi-receive-oneshot [OPTIONS] [config_file_path]

Example
-------

Transferring a file over a loopback diode, from stdin to stdout, using UDP port 6000:

.. code-block:: bash

   # Receiver: writes what it receives to result.bin.
   # The --to endpoint is a mandatory placeholder; output always goes to stdout.
   $ lidi-receive-oneshot --from 127.0.0.1 --ports 6000 --to tcp:127.0.0.1:9999 > result.bin

   # Sender: reads source.bin from stdin
   $ lidi-send-oneshot --to 127.0.0.1 --ports 6000 < source.bin

.. note::
   Since a oneshot transfer is a single stream that terminates when stdin reaches end-of-file, the end of the input closes the transfer and flushes the last (possibly partial) RaptorQ block, so no ``flush`` option is required.
