use lidi_command_utils::config;
use lidi_protocol as protocol;
use std::{io, process, thread};

struct Lifecycle {}

impl lidi_receive::ClientLifecycle for Lifecycle {
    fn start(
        &self,
        _endpoint: &lidi_command_utils::config::Endpoint,
        _client_id: protocol::ClientId,
    ) -> Result<Box<dyn lidi_receive::Client>, lidi_receive::Error> {
        Ok(Box::new(io::stdout()))
    }

    fn end(
        &self,
        _client: Box<dyn lidi_receive::Client>,
        ok: bool,
    ) -> Result<(), lidi_receive::Error> {
        if ok {
            process::exit(0);
        } else {
            process::exit(1);
        }
    }
}

fn main() {
    let config = match lidi_command_utils::command_arguments(
        lidi_command_utils::Role::Receive,
        true,
        false,
        false,
    ) {
        Ok(config) => config,
        Err(e) => {
            eprintln!("{e}");
            return;
        }
    };

    let mut config = config::ReceiveConfig::from(config);

    #[cfg(feature = "jemalloc")]
    log::info!("using jemalloc as global allocator");
    #[cfg(all(not(feature = "jemalloc"), feature = "mimalloc"))]
    log::info!("using mimalloc as global allocator");

    let raptorq = match protocol::RaptorQ::new(
        config.common.mtu(),
        config.common.block(),
        config.common.repair(),
    ) {
        Ok(raptorq) => raptorq,
        Err(e) => {
            log::error!("{e}");
            return;
        }
    };

    config.common.max_clients = Some(1);
    config.common.heartbeat = None;

    let lifecycle = Lifecycle {};

    let receiver = match lidi_receive::Receiver::new(&config, raptorq, lifecycle) {
        Ok(receiver) => receiver,
        Err(e) => {
            log::error!("{e}");
            return;
        }
    };

    thread::scope(|scope| {
        if let Err(e) = receiver.start(scope) {
            log::error!("failed to start diode receiver: {e}");
        }
    });
}
