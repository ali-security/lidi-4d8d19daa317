use std::{collections, io::Write, os::fd::AsRawFd};

use lidi_command_utils::config;
use lidi_protocol as protocol;

pub fn start<C, ClientNew, ClientEnd, E>(
    receiver: &crate::Receiver<ClientNew, ClientEnd>,
    thread_number: u32,
    client_id: protocol::ClientId,
    recvq: &crossbeam_channel::Receiver<protocol::Block>,
    to_client: &crossbeam_channel::Sender<protocol::Block>,
    hash: bool,
) -> Result<(), crate::Error>
where
    C: Write + AsRawFd,
    ClientNew: Send + Sync + Fn(&config::Endpoint, protocol::ClientId) -> Result<C, E>,
    ClientEnd: Send + Sync + Fn(C, bool),
    E: Into<crate::Error>,
{
    let mut expected_sequence_number = 1; // 0 is consumed by the Start
    let mut parked = collections::HashMap::new();

    #[cfg(not(feature = "hash"))]
    if hash {
        log::warn!("hash was not enabled at compilation, ignoring this parameter");
    }

    #[cfg(feature = "hash")]
    let mut hasher = if hash {
        Some(lidi_command_utils::hash::StreamHasher::default())
    } else {
        None
    };

    #[cfg(feature = "prometheus")]
    let gauge_parked = metrics::gauge!(format!("lidi_client_{thread_number}_parked_size"));
    #[cfg(feature = "prometheus")]
    let gauge_queue = metrics::gauge!(format!("lidi_client_{thread_number}_queue_len"));

    loop {
        let block = if let Some(block) = parked.remove(&expected_sequence_number) {
            #[cfg(feature = "prometheus")]
            #[allow(clippy::cast_precision_loss)]
            gauge_parked.set(parked.len() as f64);
            if parked.len() < parked.capacity() / 2 {
                parked.shrink_to_fit();
            }
            block
        } else if let Some(timeout) = receiver.config.abort_timeout {
            recvq.recv_timeout(timeout).map_err(crate::Error::from)?
        } else {
            recvq.recv().map_err(crate::Error::from)?
        };

        #[cfg(feature = "prometheus")]
        #[allow(clippy::cast_precision_loss)]
        gauge_queue.set(recvq.len() as f64);

        let sequence_number = block.sequence_number();

        log::trace!("client {client_id:x}: receiving block with sequence number {sequence_number}");

        if sequence_number != expected_sequence_number {
            log::trace!(
                "client {client_id:x}: parking block (sequence number {sequence_number} != {expected_sequence_number})"
            );
            if parked.insert(sequence_number, block).is_some() {
                return Err(crate::Error::Internal(format!(
                    "duplicate sequence number {sequence_number}"
                )));
            }
            continue;
        }

        #[cfg(feature = "hash")]
        if let Some(hasher) = hasher.as_mut() {
            hasher.update(block.payload());
        }

        let block_type = block.block_type()?;

        to_client.send(block)?;

        if matches!(
            block_type,
            protocol::BlockType::Abort | protocol::BlockType::End
        ) {
            #[cfg(feature = "hash")]
            if let Some(hasher) = hasher {
                let hash = hasher.finalize();
                log::info!("client {client_id:x}: hash is {hash:x}");
            }
            break;
        }

        expected_sequence_number = expected_sequence_number.wrapping_add(1);
    }

    Ok(())
}
