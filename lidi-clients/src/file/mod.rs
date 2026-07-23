//! Module for sending/receiving entire files into/from Lidi TCP or Unix sockets

#[cfg(feature = "tls")]
use crate::tls;
use std::{fmt, io, num};

/// On-the-wire framing of the file transfer protocol.
pub mod protocol;
/// Receiving side of the file transfer protocol.
pub mod receive;
/// Sending side of the file (and directory) transfer protocol.
pub mod send;

/// Configuration of a file transfer client, parameterized by the diode connection type `D`
/// ([`crate::DiodeSend`] when sending, [`crate::DiodeReceive`] when receiving).
#[allow(clippy::struct_excessive_bools)]
pub struct Config<D> {
    /// The diode endpoint to connect to (sending) or listen on (receiving).
    pub diode: D,
    /// Size in bytes of the client read/write buffer.
    pub buffer_size: usize,
    /// Compute (sending) or verify (receiving) the hash of file content.
    #[cfg(feature = "hash")]
    pub hash: bool,
    /// Stop after this many files (`0` means unlimited).
    pub max_files: usize,
    /// Overwrite existing files (receiving side).
    pub overwrite: bool,
    /// Write to a temporary file and rename atomically on completion (receiving side).
    #[cfg(feature = "tmp-file")]
    pub use_tmp_file: bool,
    /// Regex of file names to ignore (directory sending).
    pub ignore: Option<regex::Regex>,
    /// Recurse into sub-directories (directory sending).
    pub recursive: bool,
    /// Watch the directory for new files (directory sending).
    pub watch: bool,
    /// TLS material for `tls:` connections.
    pub tls: crate::Tls,
}

/// Errors returned by the file transfer client.
pub enum Error {
    /// An underlying I/O operation failed.
    Io(io::Error),
    /// A file transfer protocol error occurred.
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
            Self::Other(e) => write!(fmt, "{e}"),
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

impl From<num::TryFromIntError> for Error {
    fn from(e: num::TryFromIntError) -> Self {
        Self::Other(e.to_string())
    }
}

#[cfg(feature = "tls")]
impl From<tls::Error> for Error {
    fn from(e: tls::Error) -> Self {
        Self::Tls(e)
    }
}
