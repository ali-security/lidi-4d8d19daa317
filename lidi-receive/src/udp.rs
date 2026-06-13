//! Worker that actually receives packets from the UDP diode link

use crate::socket;
use std::{
    io,
    net::{self, ToSocketAddrs},
};

pub fn start<ClientNew, ClientEnd>(
    receiver: &crate::Receiver<ClientNew, ClientEnd>,
    port: u16,
    #[cfg(not(feature = "receive-mmsg"))] to_reblock: &crossbeam_channel::Sender<
        raptorq::EncodingPacket,
    >,
    #[cfg(feature = "receive-mmsg")] to_reblock: &crossbeam_channel::Sender<
        Vec<raptorq::EncodingPacket>,
    >,
) -> Result<(), crate::Error> {
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

    socket::set_socket_recv_buffer_size(&socket, buffer_size)?;
    let sock_buffer_size = socket::get_socket_recv_buffer_size(&socket)?;
    log::info!("UDP socket receive buffer size set to {sock_buffer_size}");

    if sock_buffer_size < buffer_size {
        log::warn!(
            "UDP socket recv buffer may be too small ({sock_buffer_size} < {buffer_size}) to achieve optimal performances"
        );
        log::warn!("Please review the kernel parameters using sysctl");
    }

    let mut udp = socket::Receive::new(socket, receiver.config.mtu, receiver.config.mode)?;

    loop {
        match udp.recv()? {
            #[cfg(any(feature = "receive-native", feature = "receive-msg"))]
            socket::ReceiveDatagrams::Single(datagram) => {
                #[cfg(feature = "prometheus")]
                metrics::counter!("lidi_receive_udp_packets").increment(1);
                let packet = raptorq::EncodingPacket::deserialize(datagram);
                #[cfg(not(feature = "receive-mmsg"))]
                receiver.to_reblock.send(packet)?;
                #[cfg(feature = "receive-mmsg")]
                to_reblock.send(vec![packet])?;
            }
            #[cfg(feature = "receive-mmsg")]
            socket::ReceiveDatagrams::Multiple(datagrams) => {
                #[cfg(feature = "prometheus")]
                metrics::counter!("lidi_receive_udp_packets").increment(datagrams.len() as u64);
                let packets: Vec<_> = datagrams
                    .into_iter()
                    .map(raptorq::EncodingPacket::deserialize)
                    .collect();
                log::trace!("UDP recv: sending {} packets to reblock queue", packets.len());
                to_reblock.send(packets)?;
            }
        }
    }
}
