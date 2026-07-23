//! Worker that actually receives packets from the UDP diode link

use crate::{ClientLifecycle, reblock, socket};
use lidi_protocol as protocol;
use std::{
    io,
    net::{self, ToSocketAddrs},
};

pub fn start<Lifecycle>(
    receiver: &crate::Receiver<Lifecycle>,
    port: u16,
    to_reblock: &crossbeam_channel::Sender<reblock::Message>,
) -> Result<(), crate::Error>
where
    Lifecycle: ClientLifecycle,
{
    let addresses = (receiver.config.from.as_str(), 0)
        .to_socket_addrs()
        .map_err(|e| {
            io::Error::new(
                io::ErrorKind::AddrNotAvailable,
                format!("bad IP or hostname {:?}: {e}", receiver.config.from),
            )
        })?
        .filter(net::SocketAddr::is_ipv4)
        .collect::<Vec<_>>();
    let address = if addresses.len() == 1 {
        addresses[0].ip()
    } else {
        return Err(crate::Error::Io(io::Error::new(
            io::ErrorKind::AddrNotAvailable,
            format!("hostname matches several addresses for UDP source: {addresses:?}"),
        )));
    };

    log::info!(
        "listening for UDP packets at {}:{} with MTU {}",
        address,
        port,
        receiver.config.mtu,
    );

    let socket = net::UdpSocket::bind((address, port))?;
    socket.set_nonblocking(false)?;

    let buffer_size = u32::from(super::reblock::WINDOW_WIDTH)
        * receiver.raptorq.nb_packets()
        * u32::from(receiver.config.mtu);
    let buffer_size = i32::try_from(buffer_size)
        .map_err(|e| crate::Error::Internal(format!("nb_packets: {e}")))?;

    if let Err(e) = socket::set_socket_recv_buffer_size(&socket, buffer_size) {
        log::warn!("failed to set socket recv buffer size: {e}");
    }
    let sock_buffer_size = socket::get_socket_recv_buffer_size(&socket)?;
    log::info!("UDP socket receive buffer size set to {sock_buffer_size}");

    if sock_buffer_size < buffer_size {
        log::warn!(
            "UDP socket recv buffer may be too small ({sock_buffer_size} < {buffer_size}) to achieve optimal performances"
        );
        log::warn!("Please review the kernel parameters using sysctl");
    }

    let mut session_id = 0;

    let mut udp = socket::Receive::new(socket, receiver.config.mtu, receiver.config.mode)?;

    loop {
        match udp.recv()? {
            #[cfg(any(feature = "receive-native", feature = "receive-msg"))]
            socket::ReceiveDatagrams::Single(datagram) => {
                #[cfg(feature = "prometheus")]
                metrics::counter!("lidi_receive_udp_packets").increment(1);

                let (datagram_session_id, packet) = protocol::session_split(datagram);

                if session_id == 0 {
                    session_id = datagram_session_id;
                    log::debug!("session is {session_id:x}");
                    to_reblock.send(reblock::Message::NewSession(session_id))?;
                } else if datagram_session_id != session_id {
                    session_id = datagram_session_id;
                    log::debug!("new session is {session_id:x}");
                    to_reblock.send(reblock::Message::NewSession(session_id))?;
                }

                let packet = raptorq::EncodingPacket::deserialize(packet);

                #[cfg(not(feature = "receive-mmsg"))]
                to_reblock.send(reblock::Message::Packet(packet))?;
                #[cfg(feature = "receive-mmsg")]
                to_reblock.send(reblock::Message::Packets(vec![packet]))?;
            }
            #[cfg(feature = "receive-mmsg")]
            socket::ReceiveDatagrams::Multiple(datagrams) => {
                #[cfg(feature = "prometheus")]
                metrics::counter!("lidi_receive_udp_packets").increment(datagrams.len() as u64);

                // assume all datagrams are from the same session
                let datagram_session_id = protocol::session_split(datagrams[0]).0;

                if session_id == 0 {
                    session_id = datagram_session_id;
                    log::debug!("session is {session_id:x}");
                    to_reblock.send(reblock::Message::NewSession(session_id))?;
                } else if datagram_session_id != session_id {
                    session_id = datagram_session_id;
                    log::debug!("new session is {session_id:x}");
                    to_reblock.send(reblock::Message::NewSession(session_id))?;
                }

                let packets: Vec<_> = datagrams
                    .into_iter()
                    .filter_map(|datagram| {
                        let (datagram_session_id, datagram) = protocol::session_split(datagram);
                        if datagram_session_id == session_id {
                            Some(raptorq::EncodingPacket::deserialize(datagram))
                        } else {
                            None
                        }
                    })
                    .collect();
                log::trace!(
                    "UDP recv: sending {} packets to reblock queue",
                    packets.len()
                );
                to_reblock.send(reblock::Message::Packets(packets))?;
            }
        }
    }
}
