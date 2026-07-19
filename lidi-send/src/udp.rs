//! Worker that encodes protocol blocks into `RaptorQ` packets

use crate::socket;
use lidi_protocol as protocol;
use std::{
    io, iter,
    net::{self, ToSocketAddrs},
};

pub fn start<C>(
    sender: &crate::Sender<C>,
    to_port: u16,
    for_udp: &crossbeam_channel::Receiver<Option<Vec<raptorq::EncodingPacket>>>,
) -> Result<(), crate::Error> {
    let socket = net::UdpSocket::bind(sender.config.to_bind)?;
    socket.set_nonblocking(false)?;

    let buffer_size = sender.raptorq.nb_packets() * u32::from(sender.config.mtu);
    let buffer_size = i32::try_from(buffer_size)
        .map_err(|e| crate::Error::Internal(format!("too large buffer size: {e}")))?;

    if let Err(e) = socket::set_socket_send_buffer_size(&socket, buffer_size) {
        log::warn!("failed to set socket send buffer size: {e}");
    }
    let sock_buffer_size = socket::get_socket_send_buffer_size(&socket)?;
    log::info!("UDP socket send buffer size set to {sock_buffer_size}");

    if sock_buffer_size < buffer_size {
        log::warn!(
            "UDP socket send buffer may be too small ({sock_buffer_size} < {buffer_size}) to achieve optimal performances"
        );
        log::warn!("Please review the kernel parameters using sysctl");
    }

    let addresses = (sender.config.to.as_str(), 0)
        .to_socket_addrs()
        .map_err(|e| {
            io::Error::new(
                io::ErrorKind::AddrNotAvailable,
                format!("bad IP or hostname {:?}: {e}", sender.config.to),
            )
        })?
        .filter(net::SocketAddr::is_ipv4)
        .collect::<Vec<_>>();
    let address = if addresses.len() == 1 {
        addresses[0].ip()
    } else {
        return Err(crate::Error::Io(io::Error::new(
            io::ErrorKind::AddrNotAvailable,
            format!("hostname matches several addresses for UDP destination: {addresses:?}"),
        )));
    };

    log::info!(
        "sending UDP traffic to {}:{} with MTU {} binding to {}",
        address,
        to_port,
        sender.config.mtu,
        sender.config.to_bind
    );

    let address = net::SocketAddr::new(address, to_port);

    let mut udp = socket::Send::new(socket, address, sender.config.mode)?;

    let mut datagrams =
        vec![vec![0u8; sender.config.mtu as usize]; sender.raptorq.nb_packets() as usize];

    loop {
        let Some(packets) = for_udp.recv()? else {
            return Ok(());
        };

        let nb_packets = packets.len();

        log::debug!("sending {nb_packets} packets");

        let session_id_len = size_of::<protocol::SessionId>();

        let to_send = iter::zip(
            packets.iter().map(raptorq::EncodingPacket::serialize),
            datagrams[0..nb_packets].iter_mut(),
        )
        .map(|(packet, datagram)| {
            datagram[0..session_id_len].copy_from_slice(&sender.session_id.to_le_bytes());

            let packet_len = packet.len();

            datagram[session_id_len..session_id_len + packet_len].copy_from_slice(&packet);

            &mut datagram[0..session_id_len + packet_len]
        })
        .collect();

        if let Err(e) = udp.send(to_send) {
            log::error!("failed to send UDP packet: {e}");
            #[cfg(feature = "prometheus")]
            metrics::counter!("lidi_error_udp_packets").increment(nb_packets as u64);
        } else {
            #[cfg(feature = "prometheus")]
            metrics::counter!("lidi_send_udp_packets").increment(nb_packets as u64);
        }
    }
}
