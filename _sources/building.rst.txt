.. _Building lidi:

Building lidi
=============

Prerequisites
-------------

The only dependency needed to build lidi from source is the Rust toolchain
(``rustc`` and ``cargo``). The usual way to install it is through `rustup
<https://rustup.rs/>`_:

.. code-block:: bash

   $ rustup install stable

Some optional compilation features pull in native libraries that must be
available on the build host, most notably `OpenSSL <https://www.openssl.org/>`_
for the TLS features (``from-tls`` / ``to-tls`` / ``tls``).

Building
--------

Building lidi with its default features is straightforward:

.. code-block:: bash

   $ cargo build --release

The resulting binaries are placed in ``target/release/``. With the default
workspace members, this builds:

- the two core binaries, ``lidi-send`` and ``lidi-receive``, and their oneshot
  variants ``lidi-send-oneshot`` and ``lidi-receive-oneshot``;
- the client utilities ``lidi-file-send``, ``lidi-file-receive``,
  ``lidi-dir-send``, ``lidi-udp-send``, ``lidi-udp-receive``,
  ``lidi-flood-send``, ``lidi-flood-receive`` and ``lidi-network-simulator``;
- the C shared library (``lidi-bindings``).

Cargo workspace layout
----------------------

Lidi is a Cargo workspace made of several crates, each with its own set of
compilation features:

- ``lidi-send`` — the sender binaries.
- ``lidi-receive`` — the receiver binaries.
- ``lidi-clients`` — the file, directory and UDP-tunnel client utilities.
- ``lidi-bindings`` — the C shared library.
- ``lidi-command-utils`` — internal library shared by the binaries (command
  line, configuration, logging, sockets, TLS, hashing). Its features are enabled
  transitively by the crates above and normally do not need to be selected
  manually.
- ``lidi-protocol`` — internal library implementing the on-wire protocol. It has
  no compilation feature.

Selecting compilation features
------------------------------

All features listed below are enabled by default unless stated otherwise. To
build a crate with a custom set of features, disable the defaults and list the
ones you want. For example, to build a minimal sender that only accepts plain
TCP connections and only uses the ``sendmmsg`` UDP strategy:

.. code-block:: bash

   $ cargo build --release -p lidi-send \
       --no-default-features \
       --features "command-line,from-tcp,heartbeat,send-mmsg"

To keep the defaults and only add an opt-in feature (for instance the mimalloc
allocator):

.. code-block:: bash

   $ cargo build --release -p lidi-send --features mimalloc

.. note::
   Most features gate a runtime capability. When a configured option requires a
   feature that was not compiled in, lidi either logs a warning and ignores the
   option (``hash``, ``heartbeat``, ``log4rs``, ``prometheus``) or logs an error
   and refuses to use the corresponding endpoint (``from-*`` / ``to-*`` /
   ``tcp`` / ``tls`` / ``unix``).

Sender features (``lidi-send``)
-------------------------------

- ``command-line`` *(default)* — parse command line options with `clap` in
  addition to the configuration file. Without this feature the binary accepts
  only a single positional configuration-file path.
- ``from-tcp`` *(default)* — accept plain TCP client connections (``tcp:``
  source endpoints).
- ``from-tls`` *(default)* — accept TLS client connections (``tls:`` source
  endpoints). Pulls in OpenSSL.
- ``from-unix`` *(default)* — accept Unix-domain socket client connections
  (``unix:`` source endpoints).
- ``hash`` *(default)* — support the per-endpoint ``hash`` option (compute a hash
  of the transferred data).
- ``heartbeat`` *(default)* — send periodic heartbeat blocks (the ``heartbeat``
  parameter).
- ``log4rs`` *(default)* — support a `log4rs` YAML logging configuration file
  (``log4rs-config``).
- ``prometheus`` *(default)* — expose Prometheus metrics (``prometheus-listen``).
- ``send-native`` *(default)* — compile the ``send`` UDP strategy.
- ``send-msg`` *(default)* — compile the ``sendmsg`` UDP strategy.
- ``send-mmsg`` *(default)* — compile the ``sendmmsg`` UDP strategy.
- ``mimalloc`` *(opt-in)* — use the mimalloc global allocator instead of the
  system one.

At least one of ``send-native``, ``send-msg`` or ``send-mmsg`` must be enabled.
When several UDP strategies are compiled in, the default mode is ``mmsg``, then
``msg``, then ``native`` (see the ``mode`` parameter).

Receiver features (``lidi-receive``)
------------------------------------

- ``command-line`` *(default)* — parse command line options with `clap` in
  addition to the configuration file. Without this feature the binary accepts
  only a single positional configuration-file path.
- ``to-tcp`` *(default)* — forward to plain TCP destination endpoints (``tcp:``).
- ``to-tls`` *(default)* — forward to TLS destination endpoints (``tls:``). Pulls
  in OpenSSL.
- ``to-unix`` *(default)* — forward to Unix-domain socket destination endpoints
  (``unix:``).
- ``hash`` *(default)* — support the per-endpoint ``hash`` option (verify a hash
  of the transferred data).
- ``heartbeat`` *(default)* — monitor incoming heartbeat blocks and warn on
  sender disconnection (the ``heartbeat`` parameter).
- ``log4rs`` *(default)* — support a `log4rs` YAML logging configuration file
  (``log4rs-config``).
- ``prometheus`` *(default)* — expose Prometheus metrics (``prometheus-listen``).
- ``receive-native`` *(default)* — compile the ``recv`` UDP strategy.
- ``receive-msg`` *(default)* — compile the ``recvmsg`` UDP strategy.
- ``receive-mmsg`` *(default)* — compile the ``recvmmsg`` UDP strategy.
- ``mimalloc`` *(opt-in)* — use the mimalloc global allocator instead of the
  system one.

At least one of ``receive-native``, ``receive-msg`` or ``receive-mmsg`` must be
enabled. When several UDP strategies are compiled in, the default mode is
``mmsg``, then ``msg``, then ``native`` (see the ``mode`` parameter).

Client features (``lidi-clients``)
----------------------------------

These features apply to the file, directory and UDP-tunnel client utilities.

- ``tcp`` *(default)* — connect to / listen on plain TCP (``--to-tcp`` /
  ``--from-tcp``).
- ``tls`` *(default)* — connect to / listen on TLS (``--to-tls`` /
  ``--from-tls``). Pulls in OpenSSL.
- ``unix`` *(default)* — connect to / listen on Unix-domain sockets
  (``--to-unix`` / ``--from-unix``).
- ``hash`` *(default)* — compute (sending) or verify (receiving) file content
  hashes (``--hash``).
- ``inotify`` *(default)* — watch directories for new files using inotify
  (``lidi-dir-send --watch``). Without this feature, watching falls back to
  periodically re-scanning the directory tree.
- ``log4rs`` *(default)* — support a `log4rs` YAML logging configuration file
  (``--log-config``).

At least one of ``tcp``, ``tls`` or ``unix`` must be enabled.

C bindings features (``lidi-bindings``)
---------------------------------------

The C shared library exposes a subset of the file client. Its features simply
forward to the corresponding ``lidi-clients`` features:

- ``hash`` *(default)* — forwards to ``lidi-clients/hash``.
- ``inotify`` *(default)* — forwards to ``lidi-clients/inotify``.

Internal library features (``lidi-command-utils``)
--------------------------------------------------

``lidi-command-utils`` is not built directly; the following features are enabled
transitively by the sender, receiver and client crates and do not normally need
to be selected by hand: ``command-line`` (clap), ``hash`` (xxHash), ``log4rs``,
``mimalloc``, ``prometheus`` and ``tls`` (OpenSSL).
