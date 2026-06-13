//! Receiver functions module
//!
//! Several threads are involved in the receipt pipeline. Each worker is run with a `start`
//! function of a submodule of the [`crate::receive`] module, data being passed through
//! [`crossbeam_channel`] bounded channels to form the following data pipeline:
//!
//! ```text
//!       -----------             ------------------            ---------
//! udp --| packets |-> reblock --| vec of packets |-> decode --| block |-> dispatch
//!       -----------             ------------------            ---------
//! ```
//!
//! Notes:
//! - heartbeat does not need a dedicated worker on the receiver side, heartbeat blocks are
//!   handled by the dispatch worker,
//! - there are `max_clients` clients workers running in parallel,
//! - there are `nb_decode_threads` decode workers running in parallel.

#[cfg(not(any(feature = "receive-native", feature = "receive-msg", feature = "receive-mmsg")))]
compile_error!("at least one of receive-native, receive-msg, or receive-mmsg features must be enabled");

use lidi_command_utils::config;
#[cfg(feature = "to-tls")]
use lidi_command_utils::tls;
use lidi_protocol as protocol;
use std::{
    fmt,
    io::{self, Write},
    net,
    os::fd::AsRawFd,
    thread, time,
};

mod client;
mod client_reorder;
mod clients;
mod dispatch;
mod reblock;
mod socket;
mod udp;

pub enum Error {
    Io(io::Error),
    SendPackets,
    SendBlockPackets,
    SendBlock,
    SendClients,
    Receive(crossbeam_channel::RecvError),
    ReceiveTimeout(crossbeam_channel::RecvTimeoutError),
    Protocol(protocol::Error),
    Internal(String),
    #[cfg(feature = "to-tls")]
    Tls(lidi_command_utils::tls::Error),
}

impl fmt::Display for Error {
    fn fmt(&self, fmt: &mut fmt::Formatter<'_>) -> Result<(), fmt::Error> {
        match self {
            Self::Io(e) => write!(fmt, "I/O error: {e}"),
            Self::SendPackets => write!(fmt, "crossbeam send packets error"),
            Self::SendBlockPackets => write!(fmt, "crossbeam send block packets error"),
            Self::SendBlock => write!(fmt, "crossbeam send block error"),
            Self::SendClients => write!(fmt, "crossbeam send client error"),
            Self::Receive(e) => write!(fmt, "crossbeam receive error: {e}"),
            Self::ReceiveTimeout(e) => write!(fmt, "crossbeam receive timeout error: {e}"),
            Self::Protocol(e) => write!(fmt, "diode protocol error: {e}"),
            Self::Internal(e) => write!(fmt, "internal error: {e}"),
            #[cfg(feature = "to-tls")]
            Self::Tls(e) => write!(fmt, "TLS error: {e}"),
        }
    }
}

impl From<io::Error> for Error {
    fn from(e: io::Error) -> Self {
        Self::Io(e)
    }
}

#[cfg(not(feature = "receive-mmsg"))]
impl From<crossbeam_channel::SendError<raptorq::EncodingPacket>> for Error {
    fn from(_: crossbeam_channel::SendError<raptorq::EncodingPacket>) -> Self {
        Self::SendPackets
    }
}

#[cfg(feature = "receive-mmsg")]
impl From<crossbeam_channel::SendError<Vec<raptorq::EncodingPacket>>> for Error {
    fn from(_: crossbeam_channel::SendError<Vec<raptorq::EncodingPacket>>) -> Self {
        Self::SendPackets
    }
}

impl From<crossbeam_channel::SendError<protocol::Block>> for Error {
    fn from(_: crossbeam_channel::SendError<protocol::Block>) -> Self {
        Self::SendBlock
    }
}

impl From<crossbeam_channel::SendError<Option<protocol::Block>>> for Error {
    fn from(_: crossbeam_channel::SendError<Option<protocol::Block>>) -> Self {
        Self::SendBlock
    }
}

impl
    From<
        crossbeam_channel::SendError<(
            protocol::EndpointId,
            protocol::ClientId,
            crossbeam_channel::Receiver<protocol::Block>,
        )>,
    > for Error
{
    fn from(
        _: crossbeam_channel::SendError<(
            protocol::EndpointId,
            protocol::ClientId,
            crossbeam_channel::Receiver<protocol::Block>,
        )>,
    ) -> Self {
        Self::SendClients
    }
}

impl From<crossbeam_channel::RecvError> for Error {
    fn from(e: crossbeam_channel::RecvError) -> Self {
        Self::Receive(e)
    }
}

impl From<crossbeam_channel::RecvTimeoutError> for Error {
    fn from(e: crossbeam_channel::RecvTimeoutError) -> Self {
        Self::ReceiveTimeout(e)
    }
}

impl From<protocol::Error> for Error {
    fn from(e: protocol::Error) -> Self {
        Self::Protocol(e)
    }
}

#[cfg(feature = "to-tls")]
impl From<tls::Error> for Error {
    fn from(e: tls::Error) -> Self {
        Self::Tls(e)
    }
}

struct Config {
    mtu: u16,
    ports: Vec<u16>,
    max_clients: u32,
    #[cfg(feature = "heartbeat")]
    heartbeat: Option<time::Duration>,
    from: String,
    to: Vec<config::Endpoint>,
    reset_timeout: time::Duration,
    abort_timeout: Option<time::Duration>,
    // Per-client block queue size (0 = unbounded). Matches lidi_receive_client_queue_full.
    client_queue_size: usize,
    // Per-stage pipeline queue sizes (0 = unbounded). Match lidi_receive_*_queue_len metrics.
    reblock_queue_size: usize,
    dispatch_queue_size: usize,
    clients_queue_size: usize,
    mode: config::Mode,
    #[cfg(feature = "prometheus")]
    prometheus_listen: Option<net::SocketAddr>,
}

impl From<&config::ReceiveConfig> for Config {
    fn from(config: &config::ReceiveConfig) -> Self {
        #[cfg(not(feature = "heartbeat"))]
        if config.common.heartbeat().is_some() {
            log::warn!("heartbeat was not enabled at compilation, ignoring this parameter");
        }

        let available_modes = [
            #[cfg(feature = "receive-mmsg")]
            config::Mode::Mmsg,
            #[cfg(feature = "receive-msg")]
            config::Mode::Msg,
            #[cfg(feature = "receive-native")]
            config::Mode::Native,
        ];

        let mode = config
            .receive
            .mode()
            .filter(|mode| {
                if available_modes.contains(mode) {
                    true
                } else {
                    log::warn!("mode {mode} was not enabled at compilation");
                    false
                }
            })
            .unwrap_or_else(|| available_modes[0]);

        Self {
            mtu: config.common.mtu(),
            ports: config.common.ports(),
            max_clients: config.common.max_clients(),
            #[cfg(feature = "heartbeat")]
            heartbeat: config.common.heartbeat(),
            from: config.receive.from().into(),
            to: config.receive.to(),
            reset_timeout: config.receive.reset_timeout(),
            abort_timeout: config.receive.abort_timeout(),
            client_queue_size: config.receive.client_queue_size(),
            reblock_queue_size: config.receive.reblock_queue_size(),
            dispatch_queue_size: config.receive.dispatch_queue_size(),
            clients_queue_size: config.receive.clients_queue_size(),
            mode,
            #[cfg(feature = "prometheus")]
            prometheus_listen: config.receive.prometheus_listen(),
        }
    }
}

/// An instance of this data structure is shared by workers to synchronize them and to access
/// communication channels
pub struct Receiver<ClientNew, ClientEnd> {
    config: Config,
    raptorq: protocol::RaptorQ,
    to_dispatch: crossbeam_channel::Sender<Option<protocol::Block>>,
    for_dispatch: crossbeam_channel::Receiver<Option<protocol::Block>>,
    to_clients: crossbeam_channel::Sender<(
        protocol::EndpointId,
        protocol::ClientId,
        crossbeam_channel::Receiver<protocol::Block>,
    )>,
    for_clients: crossbeam_channel::Receiver<(
        protocol::EndpointId,
        protocol::ClientId,
        crossbeam_channel::Receiver<protocol::Block>,
    )>,
    active_transfers:
        dashmap::DashMap<protocol::ClientId, crossbeam_channel::Sender<protocol::Block>>,
    #[cfg(feature = "prometheus")]
    ended_transfers: std::sync::Arc<
        std::sync::Mutex<
            std::collections::HashMap<protocol::ClientId, crossbeam_channel::Sender<protocol::Block>>,
        >,
    >,
    #[cfg(all(feature = "prometheus", not(feature = "receive-mmsg")))]
    reblock_queues: std::sync::Arc<std::sync::Mutex<Vec<crossbeam_channel::Receiver<raptorq::EncodingPacket>>>>,
    #[cfg(all(feature = "prometheus", feature = "receive-mmsg"))]
    reblock_queues: std::sync::Arc<std::sync::Mutex<Vec<crossbeam_channel::Receiver<Vec<raptorq::EncodingPacket>>>>>,
    client_new: ClientNew,
    client_end: ClientEnd,
}

impl<C, ClientNew, ClientEnd, E> Receiver<ClientNew, ClientEnd>
where
    C: Write + AsRawFd,
    ClientNew: Send + Sync + Fn(&config::Endpoint, protocol::ClientId) -> Result<C, E>,
    ClientEnd: Send + Sync + Fn(C, bool),
    E: Into<Error>,
{
    #[cfg(feature = "prometheus")]
    #[allow(clippy::cast_precision_loss)]
    fn metrics_loop(&self) {
        let timer = time::Duration::from_secs(1);

        loop {
            thread::sleep(timer);

            if let Ok(queues) = self.reblock_queues.lock() {
                let reblock_total: usize = queues.iter().map(|q| q.len()).sum();
                log::debug!("Reblock queue metric: {} queues, total len = {}", queues.len(), reblock_total);
                metrics::gauge!("lidi_receive_reblock_queue_len").set(reblock_total as f64);
            }

            metrics::gauge!("lidi_receive_dispatch_queue_len").set(self.for_dispatch.len() as f64);
            metrics::gauge!("lidi_receive_clients_queue_len").set(self.for_clients.len() as f64);

            if let Ok(mut ended) = self.ended_transfers.lock() {
                ended.retain(|client_id, client_sendq| {
                    let retain = !client_sendq.is_empty();
                    if !retain {
                        log::debug!("purging ended transfer of client {client_id:x}");
                    }
                    retain
                });
                metrics::gauge!("lidi_receive_ended_transfers_retained").set(ended.len() as f64);
            }

            let (total, max) =
                self.active_transfers
                    .iter()
                    .fold((0usize, 0usize), |(t, m), ref_multi| {
                        let len = ref_multi.value().len();
                        (t + len, m.max(len))
                    });
            metrics::gauge!("lidi_receive_client_sendq_total_len").set(total as f64);
            metrics::gauge!("lidi_receive_client_sendq_max_len").set(max as f64);
        }
    }

    pub fn new(
        config: &config::ReceiveConfig,
        raptorq: protocol::RaptorQ,
        client_new: ClientNew,
        client_end: ClientEnd,
    ) -> Result<Self, Error> {
        let config = Config::from(config);

        let (to_dispatch, for_dispatch) = match config.dispatch_queue_size {
            0 => crossbeam_channel::unbounded(),
            n => crossbeam_channel::bounded(n),
        };
        let (to_clients, for_clients) = match config.clients_queue_size {
            0 => crossbeam_channel::unbounded(),
            n => crossbeam_channel::bounded(n),
        };

        Ok(Self {
            config,
            raptorq,
            to_dispatch,
            for_dispatch,
            to_clients,
            for_clients,
            active_transfers: dashmap::DashMap::new(),
            #[cfg(feature = "prometheus")]
            ended_transfers: std::sync::Arc::new(std::sync::Mutex::new(std::collections::HashMap::new())),
            #[cfg(feature = "prometheus")]
            reblock_queues: std::sync::Arc::new(std::sync::Mutex::new(Vec::new())),
            client_new,
            client_end,
        })
    }

    /// # Errors
    ///
    /// Will return `Err` if scoped threads cannot spawned.
    #[allow(clippy::too_many_lines)]
    pub fn start<'a>(&'a self, scope: &'a thread::Scope<'a, '_>) -> Result<(), Error> {
        log::info!(
            "max {} simultaneous clients/transfers",
            self.config.max_clients
        );

        log::info!("receive mode is {}", self.config.mode);
        log::info!("sending to {:?}", self.config.to);

        log::info!(
            "queue sizes: reblock={} dispatch={} clients={} client={}",
            self.config.reblock_queue_size,
            self.config.dispatch_queue_size,
            self.config.clients_queue_size,
            self.config.client_queue_size,
        );

        log::info!(
            "reset timeout is {} seconds",
            self.config.reset_timeout.as_secs()
        );

        if let Some(abort_timeout) = self.config.abort_timeout {
            log::info!(
                "connections abort timeout set to {} seconds",
                abort_timeout.as_secs()
            );
        } else {
            log::info!("no connection abort timeout");
        }

        #[cfg(feature = "heartbeat")]
        if let Some(hb_interval) = self.config.heartbeat {
            log::info!(
                "heartbeat interval is set to {} seconds",
                hb_interval.as_secs()
            );
        } else {
            log::info!("heartbeat is disabled");
        }

        #[cfg(feature = "prometheus")]
        if let Some(prometheus) = self.config.prometheus_listen {
            log::info!("Prometheus is set to {prometheus}");

            thread::Builder::new()
                .name(String::from("metrics"))
                .spawn_scoped(scope, move || {
                    self.metrics_loop();
                })?;
        } else {
            log::info!("Prometheus is disabled");
        }

        for i in 0..self.config.max_clients {
            thread::Builder::new()
                .name(format!("client_{i}"))
                .spawn_scoped(scope, move || {
                    if let Err(e) = clients::start(self, i) {
                        log::error!("fatal client_{i} error: {e}");
                    }
                })?;
        }

        thread::Builder::new()
            .name(String::from("dispatch"))
            .spawn_scoped(scope, move || {
                if let Err(e) = dispatch::start(self) {
                    log::error!("fatal dispatch error: {e}");
                }
            })?;

        if self.config.ports.is_empty() {
            return Err(Error::Internal(String::from("no ports configured")));
        }

        for port in &self.config.ports {
            let (to_reblock, for_reblock) = match self.config.reblock_queue_size {
                0 => crossbeam_channel::unbounded(),
                n => crossbeam_channel::bounded(n),
            };

            #[cfg(feature = "prometheus")]
            if let Ok(mut queues) = self.reblock_queues.lock() {
                queues.push(for_reblock.clone());
            }

            thread::Builder::new()
                .name(format!("reblock_{port}"))
                .spawn_scoped(scope, move || {
                    if let Err(e) = reblock::start(self, &for_reblock) {
                        log::error!("fatal reblock error: {e}");
                    }
                })?;

            thread::Builder::new()
                .name(format!("recv_{port}"))
                .spawn_scoped(scope, move || {
                    if let Err(e) = udp::start(self, *port, &to_reblock) {
                        log::error!("fatal recv_{port} error: {e}");
                    }
                })?;
        }

        log::info!(
            "RaptorQ block {} bytes in {} packets + {} repair packets ",
            self.raptorq.block_size(),
            self.raptorq.min_nb_packets(),
            self.raptorq.nb_packets() - self.raptorq.min_nb_packets(),
        );

        log::debug!("{}", self.raptorq);

        Ok(())
    }
}
