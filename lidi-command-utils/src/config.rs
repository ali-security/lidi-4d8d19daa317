use serde::Deserialize;
use std::{
    error, fmt, fs,
    io::{self, Read},
    net::{self, ToSocketAddrs},
    path,
    str::FromStr,
    time,
};

const DEFAULT_RECEIVER: &str = "127.0.0.1";
const DEFAULT_PORTS: &[u16] = &[5000];

const DEFAULT_LOG_LEVEL: log::LevelFilter = log::LevelFilter::Info;
const DEFAULT_MAX_CLIENTS: u32 = 2;
const DEFAULT_MTU: u16 = 1500;
const DEFAULT_BLOCK: u32 = 220_000;
const DEFAULT_REPAIR_PERCENTAGE: u8 = 1;
const DEFAULT_RESET_TIMEOUT_SECONDS: u64 = 2;
const DEFAULT_CLIENT_QUEUE_SIZE: usize = 0;

/// Errors that can occur while parsing an endpoint description or loading the configuration file.
#[derive(Debug)]
pub enum Error {
    /// An endpoint description string is malformed.
    Endpoint(String),
    /// Reading the configuration file failed.
    Io(io::Error),
    /// Parsing the configuration file as TOML failed.
    Parsing(toml::de::Error),
}

impl From<io::Error> for Error {
    fn from(e: io::Error) -> Self {
        Self::Io(e)
    }
}

impl From<toml::de::Error> for Error {
    fn from(e: toml::de::Error) -> Self {
        Self::Parsing(e)
    }
}

impl error::Error for Error {}

impl fmt::Display for Error {
    fn fmt(&self, fmt: &mut fmt::Formatter<'_>) -> Result<(), fmt::Error> {
        match self {
            Self::Endpoint(e) => write!(fmt, "invalid endpoint description: {e}"),
            Self::Io(e) => write!(fmt, "I/O error: {e}"),
            Self::Parsing(e) => write!(fmt, "parsing error: {e}"),
        }
    }
}

/// System call strategy used to send or receive UDP datagrams.
#[derive(Clone, Copy, PartialEq, Eq, Deserialize)]
#[cfg_attr(feature = "command-line", derive(clap::ValueEnum))]
#[serde(rename_all = "lowercase", deny_unknown_fields)]
pub enum Mode {
    /// One datagram per `send`/`recv` call.
    Native,
    /// One datagram per `sendmsg`/`recvmsg` call.
    Msg,
    /// Batched datagrams per `sendmmsg`/`recvmmsg` call (highest throughput).
    Mmsg,
}

impl fmt::Display for Mode {
    fn fmt(&self, fmt: &mut fmt::Formatter<'_>) -> Result<(), fmt::Error> {
        match self {
            Self::Native => write!(fmt, "native"),
            Self::Msg => write!(fmt, "msg"),
            Self::Mmsg => write!(fmt, "mmsg"),
        }
    }
}

/// Per-endpoint options that can be attached to an endpoint description with the
/// `[flush=...,hash=...]` syntax.
#[derive(Clone, Copy, Default, Debug)]
pub struct EndpointOptions {
    /// Flush after every read/write instead of waiting for a full block or an end-of-transfer.
    pub flush: bool,
    /// Compute (sender) or verify (receiver) a hash of the transferred data.
    pub hash: bool,
}

impl fmt::Display for EndpointOptions {
    fn fmt(&self, fmt: &mut fmt::Formatter<'_>) -> Result<(), fmt::Error> {
        write!(fmt, "flush = {}, hash = {}", self.flush, self.hash)
    }
}

impl FromStr for EndpointOptions {
    type Err = Error;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        let mut res = Self::default();
        for option in s.split(',') {
            let Some((name, value)) = option.split_once('=') else {
                return Err(Error::Endpoint(format!(
                    "invalid option format: {option:?}"
                )));
            };
            match name {
                "flush" => {
                    res.flush = bool::from_str(value)
                        .map_err(|e| Error::Endpoint(format!("unknown flush option value: {e}")))?;
                }
                "hash" => {
                    res.hash = bool::from_str(value)
                        .map_err(|e| Error::Endpoint(format!("unknown hash option value: {e}")))?;
                }
                n => return Err(Error::Endpoint(format!("unknown option {n:?}"))),
            }
        }
        Ok(res)
    }
}

/// A client endpoint: where the sender reads data from, or where the receiver forwards it to.
#[derive(Clone, Debug)]
pub enum Endpoint {
    /// A plain TCP socket endpoint.
    Tcp {
        /// Address the socket connects to or listens on.
        address: net::SocketAddr,
        /// Per-endpoint options.
        options: EndpointOptions,
    },
    /// A TLS-over-TCP socket endpoint.
    Tls {
        /// Address the socket connects to or listens on.
        address: net::SocketAddr,
        /// Per-endpoint options.
        options: EndpointOptions,
    },
    /// A Unix-domain socket endpoint.
    Unix {
        /// Path of the Unix socket.
        path: path::PathBuf,
        /// Per-endpoint options.
        options: EndpointOptions,
    },
}

impl Endpoint {
    /// Returns the [`EndpointOptions`] attached to this endpoint, whatever its kind.
    #[must_use]
    pub const fn options(&self) -> &EndpointOptions {
        match self {
            Self::Tcp { options, .. } | Self::Tls { options, .. } | Self::Unix { options, .. } => {
                options
            }
        }
    }
}

impl FromStr for Endpoint {
    type Err = Error;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        let Some((prefix, tail)) = s.split_once(':') else {
            return Err(Error::Endpoint(String::from(
                "invalid endpoint: missing prefix tcp: or tls: or unix:",
            )));
        };

        let (prefix, options) = if prefix.ends_with(']') {
            let Some((prefix, options)) = prefix.split_once('[') else {
                return Err(Error::Endpoint(String::from(
                    "missing '[' for endpoint options",
                )));
            };
            (
                prefix,
                EndpointOptions::from_str(&options[..options.len() - 1])?,
            )
        } else {
            (prefix, EndpointOptions::default())
        };

        match prefix {
            "tcp" => tail
                .to_socket_addrs()
                .map_err(|e| {
                    Error::Endpoint(format!(
                        "invalid ip:port or hostname:port for tcp endpoint {tail:?}: {e}"
                    ))
                })
                .map(|addresses| addresses.filter(net::SocketAddr::is_ipv4))
                .and_then(|addresses| {
                    let addresses = addresses.collect::<Vec<_>>();
                    if addresses.len() == 1 {
                        let address = addresses[0];
                        Ok(Self::Tcp { address, options })
                    } else {
                        Err(Error::Endpoint(format!(
                            "hostname matches several addresses for tcp endpoint: {addresses:?}"
                        )))
                    }
                }),
            "tls" => tail
                .to_socket_addrs()
                .map_err(|e| {
                    Error::Endpoint(format!(
                        "invalid ip:port or hostname:port for tcp endpoint {tail:?}: {e}"
                    ))
                })
                .map(|addresses| addresses.filter(net::SocketAddr::is_ipv4))
                .and_then(|addresses| {
                    let addresses = addresses.collect::<Vec<_>>();
                    if addresses.len() == 1 {
                        let address = addresses[0];
                        Ok(Self::Tls { address, options })
                    } else {
                        Err(Error::Endpoint(format!(
                            "hostname matches several addresses for tls endpoint: {addresses:?}"
                        )))
                    }
                }),
            "unix" => {
                let path = path::PathBuf::from(tail);
                Ok(Self::Unix { path, options })
            }
            _ => Err(Error::Endpoint(format!("unsupported prefix {prefix:?}"))),
        }
    }
}

struct EndpointVisitor;

impl serde::de::Visitor<'_> for EndpointVisitor {
    type Value = Endpoint;
    fn expecting(&self, fmt: &mut fmt::Formatter<'_>) -> Result<(), fmt::Error> {
        write!(fmt, "was expecting an endpoint definition")
    }

    fn visit_str<E>(self, v: &str) -> Result<Self::Value, E>
    where
        E: serde::de::Error,
    {
        Endpoint::from_str(v).map_err(serde::de::Error::custom)
    }
}

impl<'de> Deserialize<'de> for Endpoint {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        deserializer.deserialize_str(EndpointVisitor)
    }
}

/// Parameters shared by the sender and the receiver, stored at the top level of the configuration
/// file. They must be identical on both sides of the diode.
#[derive(Clone, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
#[cfg_attr(feature = "command-line", derive(clap::Parser))]
pub struct CommonConfig {
    #[serde(skip)]
    #[cfg(feature = "command-line")]
    #[cfg_attr(
        feature = "command-line",
        clap(
            value_name = "config_file_path",
            help = "Path to configuration file (will be read before applying command line arguments)"
        )
    )]
    pub(crate) config_file: Option<path::PathBuf>,
    #[cfg_attr(
        feature = "command-line",
        clap(
            long,
            value_name = "1280..9000",
            help = "MTU of the link between sender and receiver"
        )
    )]
    mtu: Option<u16>,
    #[cfg_attr(
        feature = "command-line",
        clap(
            long,
            value_name = "1..65535[, 1..65535]*",
            value_delimiter = ',',
            help = "Ports for UDP communications between sender and receiver",
        )
    )]
    ports: Option<Vec<u16>>,
    #[cfg_attr(
        feature = "command-line",
        clap(long, help = "Size in bytes of RaptorQ block")
    )]
    block: Option<u32>,
    #[cfg_attr(
        feature = "command-line",
        clap(long, help = "Percentage of additional repair RaptorQ packets")
    )]
    repair: Option<u8>,
    #[cfg_attr(
        feature = "command-line",
        clap(
            long,
            value_name = "1..65535",
            help = "Maximal number of simultaneous clients connections"
        )
    )]
    /// Maximum number of simultaneous client connections/transfers (raw, unresolved value).
    pub max_clients: Option<u32>,
    #[cfg_attr(
        feature = "command-line",
        clap(
            long,
            help = "Duration in seconds between sent/expected heartbeat message (0 to disable)"
        )
    )]
    /// Heartbeat period in seconds, `0` or unset to disable (raw, unresolved value).
    pub heartbeat: Option<u64>,
}

impl CommonConfig {
    /// MTU of the UDP link, or the default (`1500`) if unset.
    #[must_use]
    pub fn mtu(&self) -> u16 {
        self.mtu.unwrap_or(DEFAULT_MTU)
    }

    /// UDP ports used for the transfer, or the default (`[5000]`) if unset.
    #[must_use]
    pub fn ports(&self) -> Vec<u16> {
        self.ports
            .clone()
            .unwrap_or_else(|| Vec::from(DEFAULT_PORTS))
    }

    /// `RaptorQ` block size in bytes, or the default (`220000`) if unset.
    #[must_use]
    pub fn block(&self) -> u32 {
        self.block.unwrap_or(DEFAULT_BLOCK)
    }

    /// Repair packet percentage, or the default (`1`) if unset.
    #[must_use]
    pub fn repair(&self) -> u8 {
        self.repair.unwrap_or(DEFAULT_REPAIR_PERCENTAGE)
    }

    /// Maximum number of simultaneous clients, or the default (`2`) if unset.
    #[must_use]
    pub fn max_clients(&self) -> u32 {
        self.max_clients.unwrap_or(DEFAULT_MAX_CLIENTS)
    }

    /// Heartbeat period as a [`time::Duration`], or `None` when disabled (unset or `0`).
    #[must_use]
    pub fn heartbeat(&self) -> Option<time::Duration> {
        self.heartbeat
            .filter(|heartbeat| 0 < *heartbeat)
            .map(time::Duration::from_secs)
    }
}

#[derive(Clone, Copy, Default, Deserialize)]
#[serde(rename_all = "lowercase", deny_unknown_fields)]
#[cfg_attr(
    feature = "command-line",
    derive(clap::ValueEnum),
    clap(rename_all = "snake_case")
)]
/// Minimum accepted TLS protocol version.
pub enum TlsVersion {
    /// TLS 1.1.
    Tls1_1,
    /// TLS 1.2.
    Tls1_2,
    /// TLS 1.3 (default).
    #[default]
    Tls1_3,
}

#[derive(Clone, Copy, Default, Deserialize)]
#[serde(rename_all = "lowercase", deny_unknown_fields)]
#[cfg_attr(
    feature = "command-line",
    derive(clap::ValueEnum),
    clap(rename_all = "snake_case")
)]
/// Preset `OpenSSL` server configuration profile (Mozilla recommendations).
#[allow(non_camel_case_types)]
pub enum TlsMethod {
    /// Mozilla "Intermediate" profile, revision 4.
    Mozilla_Intermediate_v4,
    /// Mozilla "Intermediate" profile, revision 5.
    Mozilla_Intermediate_v5,
    /// Mozilla "Modern" profile, revision 4.
    Mozilla_Modern_v4,
    /// Mozilla "Modern" profile, revision 5 (default).
    #[default]
    Mozilla_Modern_v5,
}

/// TLS material and settings for `tls:` endpoints, from the `[send.tls]` / `[receive.tls]`
/// configuration tables or the `--tls-*` command line options.
#[derive(Clone, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
#[cfg_attr(feature = "command-line", derive(clap::Parser))]
pub struct TlsConfig {
    #[cfg_attr(
        feature = "command-line",
        clap(
            value_name = "key_file_path",
            long = "tls-key",
            help = "Path to PEM key file"
        )
    )]
    pub(crate) key: Option<path::PathBuf>,
    #[cfg_attr(
        feature = "command-line",
        clap(
            value_name = "certificate_file_path",
            long = "tls-certificate",
            help = "Path to PEM certificate file"
        )
    )]
    pub(crate) certificate: Option<path::PathBuf>,
    #[cfg_attr(
        feature = "command-line",
        clap(
            value_name = "ca_file_path",
            long = "tls-ca",
            help = "Path to PEM accepted CA file"
        )
    )]
    pub(crate) ca: Option<path::PathBuf>,
    #[cfg_attr(
        feature = "command-line",
        clap(long = "tls-min", help = "Minimum TLS accepted version")
    )]
    pub(crate) tls_min: Option<TlsVersion>,
    #[cfg_attr(
        feature = "command-line",
        clap(long = "tls-method", help = "Minimum TLS accepted method")
    )]
    pub(crate) tls_method: Option<TlsMethod>,
    #[cfg_attr(
        feature = "command-line",
        clap(long = "tls-ciphers", help = "Accepted TLS ciphers")
    )]
    pub(crate) ciphers: Option<String>,
    #[cfg_attr(
        feature = "command-line",
        clap(long = "tls-groups", help = "Accepted TLS groups")
    )]
    pub(crate) groups: Option<String>,
}

/// Receiver-specific parameters, from the `[receive]` configuration section.
#[derive(Clone, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
#[cfg_attr(feature = "command-line", derive(clap::Parser))]
pub struct Receive {
    #[cfg_attr(feature = "command-line", clap(long, help = "Log level"))]
    log: Option<log::LevelFilter>,
    #[cfg_attr(
        feature = "command-line",
        clap(
            long,
            value_name = "log4rs_config_file_path",
            help = "Path to log4rs config file"
        )
    )]
    log4rs_config: Option<path::PathBuf>,
    #[cfg_attr(
        feature = "command-line",
        clap(
            long,
            value_name = "ip:port",
            help = "Listen socket address for Prometheus connections"
        )
    )]
    prometheus_listen: Option<net::SocketAddr>,
    #[cfg_attr(feature = "command-line", clap(long,
                                              value_parser = Endpoint::from_str,
                                              help = "Add a client endpoint [tcp:<ip:port>|tls:<ip:port>|unix:<socket_path>][,<flush,hash>=<true|false>]*"))]
    to: Vec<Endpoint>,
    #[cfg_attr(
        feature = "command-line",
        clap(
            long,
            value_name = "ip|hostname",
            help = "IP address or hostname on which to listen from sender UDP packets"
        )
    )]
    from: Option<String>,
    #[cfg_attr(
        feature = "command-line",
        clap(long, help = "Mode used to receive UDP packets")
    )]
    mode: Option<Mode>,
    #[cfg_attr(
        feature = "command-line",
        clap(
            long,
            help = "Maximum number of RaptorQ blocks to buffer per client in the client queue (0 means unbounded)"
        )
    )]
    client_queue_size: Option<usize>,
    #[cfg_attr(
        feature = "command-line",
        clap(
            long,
            help = "Maximum items in to_reblock pipeline queue (0 means unbounded)"
        )
    )]
    reblock_queue_size: Option<usize>,
    #[cfg_attr(
        feature = "command-line",
        clap(
            long,
            help = "Maximum items in to_dispatch pipeline queue (0 means unbounded)"
        )
    )]
    dispatch_queue_size: Option<usize>,
    #[cfg_attr(
        feature = "command-line",
        clap(
            long,
            help = "Maximum items in to_clients pipeline queue (0 means unbounded)"
        )
    )]
    clients_queue_size: Option<usize>,
    #[cfg_attr(
        feature = "command-line",
        clap(
            long,
            help = "Duration in seconds without UDP packets before resetting the internal state of the RaptorQ receiver"
        )
    )]
    reset_timeout: Option<u64>,
    #[cfg_attr(
        feature = "command-line",
        clap(
            long,
            help = "Duration in seconds without data for a client before closing the client connection"
        )
    )]
    abort_timeout: Option<u64>,
    #[cfg_attr(feature = "command-line", clap(flatten))]
    tls: Option<TlsConfig>,
}

impl Receive {
    #[must_use]
    pub(crate) fn log(&self) -> log::LevelFilter {
        self.log.unwrap_or(DEFAULT_LOG_LEVEL)
    }

    #[must_use]
    pub(crate) fn log4rs_config(&self) -> Option<path::PathBuf> {
        self.log4rs_config.clone()
    }

    /// Address the Prometheus exporter should listen on, if enabled.
    #[must_use]
    pub const fn prometheus_listen(&self) -> Option<net::SocketAddr> {
        self.prometheus_listen
    }

    /// Destination endpoints data is forwarded to.
    #[must_use]
    pub fn to(&self) -> Vec<Endpoint> {
        self.to.clone()
    }

    /// IP address or hostname to listen on for sender UDP packets, or the default (`127.0.0.1`).
    #[must_use]
    pub fn from(&self) -> &str {
        self.from.as_ref().map_or(DEFAULT_RECEIVER, String::as_str)
    }

    /// UDP receive mode, or `None` to let the receiver pick the best available one.
    #[must_use]
    pub const fn mode(&self) -> Option<Mode> {
        self.mode
    }

    /// Maximum number of `RaptorQ` blocks buffered per client (`0` means unbounded).
    #[must_use]
    pub fn client_queue_size(&self) -> usize {
        self.client_queue_size.unwrap_or(DEFAULT_CLIENT_QUEUE_SIZE)
    }

    /// Maximum items in the reblock pipeline queue (`0` means unbounded).
    #[must_use]
    pub fn reblock_queue_size(&self) -> usize {
        self.reblock_queue_size.unwrap_or(0)
    }

    /// Maximum items in the dispatch pipeline queue (`0` means unbounded).
    #[must_use]
    pub fn dispatch_queue_size(&self) -> usize {
        self.dispatch_queue_size.unwrap_or(0)
    }

    /// Maximum items in the clients pipeline queue (`0` means unbounded).
    #[must_use]
    pub fn clients_queue_size(&self) -> usize {
        self.clients_queue_size.unwrap_or(0)
    }

    /// Duration without UDP packets before the `RaptorQ` internal state is reset, or the default
    /// (`2` seconds).
    #[must_use]
    pub fn reset_timeout(&self) -> time::Duration {
        time::Duration::from_secs(self.reset_timeout.unwrap_or(DEFAULT_RESET_TIMEOUT_SECONDS))
    }

    /// Duration without data for a client before its connection is closed, or `None` when disabled.
    #[must_use]
    pub fn abort_timeout(&self) -> Option<time::Duration> {
        self.abort_timeout.map(time::Duration::from_secs)
    }

    /// Returns the TLS configuration, or a default one when none was provided.
    #[must_use]
    pub fn tls(&self) -> TlsConfig {
        self.tls.clone().unwrap_or_default()
    }

    /// Returns a mutable reference to the TLS configuration, creating a default one if needed.
    #[must_use]
    #[allow(clippy::missing_panics_doc)]
    pub fn tls_mut(&mut self) -> &mut TlsConfig {
        if self.tls.is_none() {
            self.tls = Some(TlsConfig::default());
        }
        self.tls.as_mut().unwrap()
    }
}

/// Sender-specific parameters, from the `[send]` configuration section.
#[derive(Clone, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
#[cfg_attr(feature = "command-line", derive(clap::Parser))]
pub struct Send {
    #[cfg_attr(feature = "command-line", clap(long, help = "Log level"))]
    log: Option<log::LevelFilter>,
    #[cfg_attr(
        feature = "command-line",
        clap(
            long,
            value_name = "log4rs_config_file_path",
            help = "Path to log4rs config file"
        )
    )]
    log4rs_config: Option<path::PathBuf>,
    #[cfg_attr(
        feature = "command-line",
        clap(
            long,
            value_name = "ip:port|hostname:port",
            help = "Listen socket address for Prometheus connections"
        )
    )]
    prometheus_listen: Option<net::SocketAddr>,
    #[cfg_attr(feature = "command-line", clap(long,
                                              value_parser = Endpoint::from_str,
                                              help = "Add a client endpoint [tcp:<ip:port>|tls:<ip:port>|unix:<socket_path>][,<flush,hash>=<true|false>]*"))]
    from: Vec<Endpoint>,
    #[cfg_attr(
        feature = "command-line",
        clap(
            long,
            value_name = "ip|hostname",
            help = "IP address or hostname of receiver"
        )
    )]
    to: Option<String>,
    #[cfg_attr(
        feature = "command-line",
        clap(
            long,
            value_name = "ip:port|hostname:port",
            help = "Binding address of UDP socket used to reach receiver"
        )
    )]
    to_bind: Option<net::SocketAddr>,
    #[cfg_attr(
        feature = "command-line",
        clap(long, help = "Mode used to send UDP packets")
    )]
    mode: Option<Mode>,
    #[cfg_attr(feature = "command-line", clap(flatten))]
    tls: Option<TlsConfig>,
}

impl Send {
    #[must_use]
    pub(crate) fn log(&self) -> log::LevelFilter {
        self.log.unwrap_or(DEFAULT_LOG_LEVEL)
    }

    #[must_use]
    pub(crate) fn log4rs_config(&self) -> Option<path::PathBuf> {
        self.log4rs_config.clone()
    }

    /// Address the Prometheus exporter should listen on, if enabled.
    #[must_use]
    pub const fn prometheus_listen(&self) -> Option<net::SocketAddr> {
        self.prometheus_listen
    }

    /// Source endpoints data is read from.
    #[must_use]
    pub fn from(&self) -> Vec<Endpoint> {
        self.from.clone()
    }

    /// IP address or hostname of the receiver, or the default (`127.0.0.1`).
    #[must_use]
    pub fn to(&self) -> &str {
        self.to.as_ref().map_or(DEFAULT_RECEIVER, String::as_str)
    }

    /// Local address the UDP socket binds to, or `0.0.0.0:0` by default.
    #[must_use]
    pub fn to_bind(&self) -> net::SocketAddr {
        let ip4 = net::Ipv4Addr::UNSPECIFIED;
        self.to_bind
            .unwrap_or_else(|| net::SocketAddr::new(net::IpAddr::V4(ip4), 0))
    }

    /// UDP send mode, or `None` to let the sender pick the best available one.
    #[must_use]
    pub const fn mode(&self) -> Option<Mode> {
        self.mode
    }

    /// Returns the TLS configuration, or a default one when none was provided.
    #[must_use]
    pub fn tls(&self) -> TlsConfig {
        self.tls.clone().unwrap_or_default()
    }

    /// Returns a mutable reference to the TLS configuration, creating a default one if needed.
    #[must_use]
    #[allow(clippy::missing_panics_doc)]
    pub fn tls_mut(&mut self) -> &mut TlsConfig {
        if self.tls.is_none() {
            self.tls = Some(TlsConfig::default());
        }
        self.tls.as_mut().unwrap()
    }
}

/// Full configuration seen by the receiver binary: common parameters plus the `[receive]` section.
#[cfg_attr(feature = "command-line", derive(clap::Parser))]
#[derive(Default)]
pub struct ReceiveConfig {
    /// Parameters common to both sides.
    #[cfg_attr(feature = "command-line", clap(flatten))]
    pub common: CommonConfig,
    /// Receiver-specific parameters.
    #[cfg_attr(feature = "command-line", clap(flatten))]
    pub receive: Receive,
}

impl From<Config> for ReceiveConfig {
    fn from(config: Config) -> Self {
        Self {
            common: config.common,
            receive: config.receive,
        }
    }
}

/// Full configuration seen by the sender binary: common parameters plus the `[send]` section.
#[cfg_attr(feature = "command-line", derive(clap::Parser))]
#[derive(Default)]
pub struct SendConfig {
    /// Parameters common to both sides.
    #[cfg_attr(feature = "command-line", clap(flatten))]
    pub common: CommonConfig,
    /// Sender-specific parameters.
    #[cfg_attr(feature = "command-line", clap(flatten))]
    pub send: Send,
}

impl From<Config> for SendConfig {
    fn from(config: Config) -> Self {
        Self {
            common: config.common,
            send: config.send,
        }
    }
}

/// Complete deserialized configuration file, holding the common parameters and both the
/// `[send]` and `[receive]` sections.
#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Config {
    #[serde(flatten)]
    pub(crate) common: CommonConfig,
    pub(crate) receive: Receive,
    pub(crate) send: Send,
}

pub(crate) fn parse(file: path::PathBuf) -> Result<Config, Error> {
    let mut file = fs::OpenOptions::new().read(true).write(false).open(file)?;
    let mut content = String::new();
    file.read_to_string(&mut content)?;
    Ok(Config::deserialize(toml::Deserializer::parse(&content)?)?)
}
