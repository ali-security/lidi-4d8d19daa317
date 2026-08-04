use std::{io, mem, net};
#[cfg(unix)]
use std::{pin, ptr};

#[cfg(not(target_os = "freebsd"))]
type TypeConstMmsgBatchSize = u32;
#[cfg(target_os = "freebsd")]
type TypeConstMmsgBatchSize = usize;

pub const MAX_MMSG_BATCH_SIZE: TypeConstMmsgBatchSize = 1024;

#[cfg(unix)]
pub fn convert_address(
    dest: net::SocketAddr,
) -> Result<(pin::Pin<Box<libc::sockaddr>>, usize), io::Error> {
    let (dest, dest_len) = match dest {
        net::SocketAddr::V4(addr4) => {
            let addr = libc::sockaddr_in {
                sin_family: libc::sa_family_t::try_from(libc::AF_INET).map_err(|e| {
                    io::Error::new(io::ErrorKind::InvalidData, format!("libc::AF_INET: {e}"))
                })?,
                sin_addr: libc::in_addr {
                    s_addr: u32::from_le_bytes(addr4.ip().octets()),
                },
                sin_port: addr4.port().to_be(),
                sin_zero: [0; 8],
                #[cfg(target_os = "freebsd")]
                sin_len: 0,
            };
            let addr = Box::new(addr);
            (
                unsafe {
                    mem::transmute::<
                        std::boxed::Box<libc::sockaddr_in>,
                        std::boxed::Box<libc::sockaddr>,
                    >(addr)
                },
                mem::size_of::<libc::sockaddr_in>(),
            )
        }
        net::SocketAddr::V6(addr6) => {
            let addr = libc::sockaddr_in6 {
                sin6_family: libc::sa_family_t::try_from(libc::AF_INET6).map_err(|e| {
                    io::Error::new(io::ErrorKind::InvalidData, format!("libc::AF_INET6: {e}"))
                })?,
                sin6_port: addr6.port().to_be(),
                sin6_flowinfo: addr6.flowinfo(),
                sin6_addr: libc::in6_addr {
                    s6_addr: addr6.ip().octets(),
                },
                sin6_scope_id: addr6.scope_id(),
                #[cfg(target_os = "freebsd")]
                sin6_len: 0,
            };
            let addr = Box::new(addr);
            (
                unsafe {
                    mem::transmute::<
                        std::boxed::Box<libc::sockaddr_in6>,
                        std::boxed::Box<libc::sockaddr>,
                    >(addr)
                },
                mem::size_of::<libc::sockaddr_in6>(),
            )
        }
    };

    Ok((pin::Pin::new(dest), dest_len))
}

// Windows' `SOL_SOCKET`/`SO_SNDBUF`/`SO_RCVBUF` and `WSAGetLastError` aren't exposed by the
// `libc` crate for this target (only the `getsockopt`/`setsockopt` prototypes are), so they're
// declared here instead of pulling in a socket-abstraction crate for four constants and one
// error accessor.
#[cfg(windows)]
mod windows_sys {
    pub const SOL_SOCKET: i32 = 0xffff;
    pub const SO_SNDBUF: i32 = 0x1001;
    pub const SO_RCVBUF: i32 = 0x1002;

    unsafe extern "system" {
        #[link_name = "WSAGetLastError"]
        pub fn wsa_get_last_error() -> i32;
    }
}

#[cfg(unix)]
use libc::{SO_RCVBUF, SO_SNDBUF};
#[cfg(windows)]
use windows_sys::{SO_RCVBUF, SO_SNDBUF};

#[cfg(unix)]
fn raw_socket(socket: &net::UdpSocket) -> libc::c_int {
    use std::os::fd::AsRawFd;
    socket.as_raw_fd()
}

#[cfg(windows)]
fn raw_socket(socket: &net::UdpSocket) -> libc::SOCKET {
    use std::os::windows::io::AsRawSocket;
    socket.as_raw_socket() as libc::SOCKET
}

#[cfg(all(unix, not(target_os = "freebsd")))]
fn last_errno() -> i32 {
    unsafe { *libc::__errno_location() }
}
#[cfg(target_os = "freebsd")]
fn last_errno() -> i32 {
    unsafe { *libc::__error() }
}

fn getsockopt_buffer_size(
    socket: &net::UdpSocket,
    option_name: libc::c_int,
) -> Result<i32, io::Error> {
    let fd = raw_socket(socket);
    let mut sz = 0i32;

    #[cfg(unix)]
    let res = unsafe {
        let mut len = libc::socklen_t::try_from(mem::size_of::<libc::c_int>())
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, format!("len: {e}")))?;
        libc::getsockopt(
            fd,
            libc::SOL_SOCKET,
            option_name,
            ptr::addr_of_mut!(sz).cast::<libc::c_void>(),
            &raw mut len,
        )
    };
    #[cfg(windows)]
    let res = unsafe {
        let mut len = libc::c_int::try_from(mem::size_of::<libc::c_int>())
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, format!("len: {e}")))?;
        libc::getsockopt(
            fd,
            windows_sys::SOL_SOCKET,
            option_name,
            (&raw mut sz).cast::<libc::c_char>(),
            &raw mut len,
        )
    };

    if res == 0 {
        Ok(sz)
    } else {
        #[cfg(unix)]
        let code = last_errno();
        #[cfg(windows)]
        let code = unsafe { windows_sys::wsa_get_last_error() };
        Err(io::Error::other(format!(
            "getsockopt returned {res}, error code == {code}",
        )))
    }
}

fn setsockopt_buffer_size(
    socket: &net::UdpSocket,
    size: i32,
    option_name: libc::c_int,
) -> Result<(), io::Error> {
    let fd = raw_socket(socket);

    #[cfg(unix)]
    let res = unsafe {
        let len = libc::socklen_t::try_from(mem::size_of::<libc::c_int>())
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, format!("len: {e}")))?;
        libc::setsockopt(
            fd,
            libc::SOL_SOCKET,
            option_name,
            ptr::addr_of!(size).cast::<libc::c_void>(),
            len,
        )
    };
    #[cfg(windows)]
    let res = unsafe {
        let len = libc::c_int::try_from(mem::size_of::<libc::c_int>())
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, format!("len: {e}")))?;
        libc::setsockopt(
            fd,
            windows_sys::SOL_SOCKET,
            option_name,
            (&raw const size).cast::<libc::c_char>(),
            len,
        )
    };

    if res == 0 {
        Ok(())
    } else {
        #[cfg(unix)]
        let code = last_errno();
        #[cfg(windows)]
        let code = unsafe { windows_sys::wsa_get_last_error() };
        Err(io::Error::other(format!(
            "setsockopt returned {res}, error code == {code}",
        )))
    }
}

/// Reads the socket's send buffer size (`SO_SNDBUF`).
///
/// # Errors
///
/// Will return `Err` if the underlying `getsockopt` call fails.
pub fn get_send_buffer_size(socket: &net::UdpSocket) -> Result<i32, io::Error> {
    getsockopt_buffer_size(socket, SO_SNDBUF)
}

/// Sets the socket's send buffer size (`SO_SNDBUF`).
///
/// # Errors
///
/// Will return `Err` if the underlying `setsockopt` call fails.
pub fn set_send_buffer_size(socket: &net::UdpSocket, size: i32) -> Result<(), io::Error> {
    setsockopt_buffer_size(socket, size, SO_SNDBUF)
}

/// Reads the socket's receive buffer size (`SO_RCVBUF`).
///
/// # Errors
///
/// Will return `Err` if the underlying `getsockopt` call fails.
pub fn get_recv_buffer_size(socket: &net::UdpSocket) -> Result<i32, io::Error> {
    getsockopt_buffer_size(socket, SO_RCVBUF)
}

/// Sets the socket's receive buffer size (`SO_RCVBUF`).
///
/// # Errors
///
/// Will return `Err` if the underlying `setsockopt` call fails.
pub fn set_recv_buffer_size(socket: &net::UdpSocket, size: i32) -> Result<(), io::Error> {
    setsockopt_buffer_size(socket, size, SO_RCVBUF)
}
