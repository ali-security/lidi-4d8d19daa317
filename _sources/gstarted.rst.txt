.. _Getting started:

Getting started
===============

Installation
------------

Building lidi from source only requires the Rust toolchain (``rustc`` and ``cargo``). Once it is installed:

.. code-block:: bash

   $ cargo build --release

provides you with the two main binaries for lidi: the sender part (``lidi-send``) and the receiver part (``lidi-receive``), in addition to other utility binaries, such as file sending/receiving ones (see :ref:`Sending files with Lidi`) and their oneshot variants (see :ref:`Oneshot Lidi`). Compiled binaries are placed in ``target/release/``.

See the :ref:`Building lidi` chapter for the full build instructions and the list of available compilation features.

Setting up a simple case
------------------------

The simplest case we can set up is to have lidi sender and receiver part running on the same machine. Next, we will use the `netcat` tool to actually send and receive data over the (software) diode link.

In this example, data enters the diode over a TCP connection on port 5000, is transferred as UDP datagrams on port 6000, and is served back over a TCP connection on port 7000.

In a first terminal, we start by running the sender part of lidi:

.. code-block:: bash

   $ cargo run --release --bin lidi-send -- --from tcp:127.0.0.1:5000 --to 127.0.0.1 --ports 6000

Some information logging should show up, especially indicating that the diode accepts TCP connections on port 5000 and that the traffic will go through the diode on UDP port 6000.

Next, we run the receiving part of lidi:

.. code-block:: bash

   $ cargo run --release --bin lidi-receive -- --to tcp:127.0.0.1:7000 --from 127.0.0.1 --ports 6000

This time, logging will indicate that traffic will come up on UDP port 6000 and that transferred content will be served on TCP port 7000.

.. note::
   Warning messages about the receiver not receiving the heartbeat message may appear on the receiving part terminal. For example, this is the case if the receiver part is launched several seconds before the sender part is run.
   If it is the case, double check that the sender part is still running and that ip addresses and ports for the UDP traffic are the same on the two parts.

The diode is now waiting for TCP connections to send and receive data.
We run a first netcat instance waiting for connection on port 7000 with the following command:

.. code-block:: bash

   $ nc -lv 127.0.0.1 7000

Finally, we should be able to connect and send raw data through the diode in a fourth terminal:

.. code-block:: bash

   $ nc 127.0.0.1 5000
   Hello Lidi!
   <Ctrl-D>

The message should have been transferred with only forwarding UDP traffic, to finally show up in the first waiting netcat terminal window!

.. note::
   ``lidi-send`` fills a whole RaptorQ block (``--block`` bytes, default 220 000) before encoding and sending it. In this example the block is flushed and sent when the ``nc`` client closes the connection (``Ctrl-D``), which lidi treats as an end-of-transfer marker. To forward data immediately without waiting for the connection to close (for instance for a long-lived stream), enable the ``flush`` option on the endpoint: ``--from tcp[flush=true]:127.0.0.1:5000``.

Using a configuration file
--------------------------

For anything beyond quick tests, it is more convenient to store settings in a TOML configuration file, given as the first positional argument. Command line arguments given after the configuration file override the values read from the file:

.. code-block:: bash

   $ cargo run --release --bin lidi-send -- config.toml
   $ cargo run --release --bin lidi-send -- config.toml --repair 5

Example configuration files are provided in the ``config_examples/`` directory of the repository. See the :ref:`Command line parameters` chapter for the list of available options and their configuration-file equivalents.

Next steps is to review :ref:`Command line parameters` to adapt them to your use case, and eventually :ref:`Tweaking parameters` to achieve optimal transfer performances.
