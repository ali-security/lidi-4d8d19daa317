release:
    cargo build --release --features mimalloc

# lidi-send/lidi-receive built with default features (no mimalloc), used by
# the Valgrind scenarios: mimalloc's internal bit tricks are known to trigger
# Valgrind false positives ("uninitialised value" reports) unrelated to the
# unsafe code the tests actually exercise (send-msg/send-mmsg socket paths).
release_no_mimalloc:
    cargo build --release --package lidi-send --package lidi-receive --target-dir target/no-mimalloc

release_tcp_mmsg:
    cargo build --release --no-default-features --features from-tcp,to-tcp,tcp,receive-mmsg,send-mmsg,tcp

release_tls_native:
    cargo build --release --no-default-features --features from-tls,to-tls,tls,receive-native,send-native

grant_chroot_receive_file:
    sudo setcap cap_sys_chroot=pe target/release/lidi-file-receive

clean:
    cargo clean

fmt:
    cargo +nightly fmt

check:
    cargo check --all-targets --all-features

check_release:
    cargo check --release --features mimalloc

# Cross-compilation smoke test for FreeBSD (`rustup target add x86_64-unknown-freebsd`).
# `tls` is skipped: openssl-sys needs a cross-compiled OpenSSL (OPENSSL_DIR) that isn't
# set up here. `lidi-bindings` is skipped: its `inotify` feature is Linux-only.
# FreeBSD is otherwise a Unix target, so Unix sockets and the msg/mmsg socket paths
# compile and are exercised here.
check_freebsd:
    cargo check --target x86_64-unknown-freebsd --workspace --exclude lidi-bindings --all-targets \
        --no-default-features --features from-tcp,to-tcp,tcp,from-unix,to-unix,unix,receive-native,send-native,receive-msg,send-msg,receive-mmsg,send-mmsg,command-line,hash,heartbeat,log4rs,prometheus

# Cross-compilation smoke test for Windows (`rustup target add x86_64-pc-windows-gnu`).
# Only the portable native/TCP path is supported: no Unix sockets, no libc msg/mmsg
# batching (Linux/FreeBSD-only syscalls), no `tls` (see check_freebsd), no `inotify`
# (`lidi-bindings` skipped). See lidi-command-utils/src/socket.rs for the portable
# (socket2-based) buffer-size tuning used on this path.
check_windows:
    cargo check --target x86_64-pc-windows-gnu --workspace --exclude lidi-bindings --all-targets \
        --no-default-features --features from-tcp,to-tcp,tcp,receive-native,send-native,command-line,hash,heartbeat,log4rs,prometheus

clippy:
    cargo clippy --all-targets --all-features

bench:
    cargo bench --all-features

test:
    behave --tags=~fail features/*.feature

doc:
    sphinx-build doc doc/_build

docker-build:
    docker build --target send --tag lidi:send-tmp .
    docker build --target receive --tag lidi:receive-tmp .

cargo-hack:
    # Each crate requires at least one feature from each "OR group" to compile:
    # - lidi-send:    one of send-native/send-msg/send-mmsg, and one of from-tcp/from-tls/from-unix
    # - lidi-receive: one of receive-native/receive-msg/receive-mmsg, and one of to-tcp/to-tls/to-unix
    # - lidi-clients: one of tcp/tls/unix
    # --at-least-one-of skips combinations that don't satisfy these constraints.
    cargo hack check --feature-powerset --no-dev-deps \
        --at-least-one-of send-native,send-msg,send-mmsg \
        --at-least-one-of from-tcp,from-tls,from-unix \
        -p lidi-send
    cargo hack check --feature-powerset --no-dev-deps \
        --at-least-one-of receive-native,receive-msg,receive-mmsg \
        --at-least-one-of to-tcp,to-tls,to-unix \
        -p lidi-receive
    cargo hack check --feature-powerset --no-dev-deps \
        --at-least-one-of tcp,tls,unix \
        -p lidi-clients
