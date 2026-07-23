//! Module for sending/receiving UDP streams into/from Lidi TCP or Unix sockets

#[cfg(feature = "tls")]
use crate::tls;
use std::{fmt, io};

/// On-the-wire framing of the UDP tunnel protocol (datagram size headers).
pub mod protocol;
/// Receiving side of the UDP tunnel.
pub mod receive;
/// Sending side of the UDP tunnel.
pub mod send;

/// Configuration of a UDP tunnel client, parameterized by the diode connection type `D`
/// ([`crate::DiodeSend`] when sending, [`crate::DiodeReceive`] when receiving).
pub struct Config<D> {
    /// The diode endpoint to connect to (sending) or listen on (receiving).
    pub diode: D,
    /// Size in bytes of the datagram buffer.
    pub buffer_size: usize,
    /// TLS material for `tls:` connections.
    pub tls: crate::Tls,
}

/// Errors returned by the UDP tunnel client.
pub enum Error {
    /// An underlying I/O operation failed.
    Io(io::Error),
    /// A UDP tunnel protocol error occurred.
    Diode(protocol::Error),
    /// A TLS error occurred.
    #[cfg(feature = "tls")]
    Tls(tls::Error),
    /// Any other error, with a human-readable message.
    Other(String),
}

impl fmt::Display for Error {
    fn fmt(&self, fmt: &mut fmt::Formatter<'_>) -> Result<(), fmt::Error> {
        match self {
            Self::Io(e) => write!(fmt, "I/O error: {e}"),
            Self::Diode(e) => write!(fmt, "diode error: {e}"),
            #[cfg(feature = "tls")]
            Self::Tls(e) => write!(fmt, "TLS error: {e}"),
            Self::Other(e) => write!(fmt, "error: {e}"),
        }
    }
}

impl From<io::Error> for Error {
    fn from(e: io::Error) -> Self {
        Self::Io(e)
    }
}

impl From<protocol::Error> for Error {
    fn from(e: protocol::Error) -> Self {
        Self::Diode(e)
    }
}

#[cfg(feature = "tls")]
impl From<tls::Error> for Error {
    fn from(e: tls::Error) -> Self {
        Self::Tls(e)
    }
}
