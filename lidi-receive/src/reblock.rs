//! Worker for grouping packets according to their block numbers to handle potential UDP packets
//! reordering

use lidi_protocol as protocol;
use std::{array, mem};

pub const WINDOW_WIDTH: u8 = u8::MAX / 2;

struct Block {
    ignore: bool,
    packets: Vec<raptorq::EncodingPacket>,
}

fn send_to_decode<ClientNew, ClientEnd>(
    receiver: &crate::Receiver<ClientNew, ClientEnd>,
    id: u8,
    blocks: &mut [Block],
) -> Result<bool, crate::Error> {
    blocks[id as usize].ignore = true;

    let capacity = blocks[id as usize].packets.capacity();
    let packets = mem::replace(
        &mut blocks[id as usize].packets,
        Vec::with_capacity(capacity),
    );

    let nb_packets = packets.len();

    log::debug!("received block {id} to decode ({nb_packets} packets)");

    #[cfg(feature = "prometheus")]
    #[allow(clippy::cast_precision_loss)]
    metrics::histogram!("lidi_receive_decode_with_n_packets").record(packets.len() as f64);

    match receiver.raptorq.decode(id, packets) {
        None => {
            #[cfg(feature = "prometheus")]
            metrics::counter!("lidi_receive_blocks_decode_failed").increment(1);
            log::error!("lost block {id} (failed to decode with {nb_packets} packets)");
            receiver.to_dispatch.send(None)?;
        }
        Some(block) => {
            log::trace!("block {id} decoded ({} bytes)", block.len());

            #[cfg(feature = "prometheus")]
            metrics::counter!("lidi_receive_blocks_decoded").increment(1);

            receiver
                .to_dispatch
                .send(Some(protocol::Block::deserialize(block)))?;
        }
    }

    #[cfg(feature = "prometheus")]
    metrics::counter!("lidi_receive_blocks_reassembled").increment(1);

    log::trace!("reassembled block {id}");

    let opposite = id.wrapping_add(WINDOW_WIDTH) as usize;

    if blocks[opposite].ignore {
        blocks[opposite].ignore = false;

        if !blocks[opposite].packets.is_empty() {
            #[cfg(feature = "prometheus")]
            metrics::counter!("lidi_receive_blocks_lost").increment(1);
            log::error!("lost block {opposite} (too far)");
            log::warn!("synchronization lost received, propagating");
            receiver.to_dispatch.send(None)?;
            return Ok(true);
        }
    }

    Ok(false)
}

pub fn start<ClientNew, ClientEnd>(
    receiver: &crate::Receiver<ClientNew, ClientEnd>,
    #[cfg(not(feature = "receive-mmsg"))] for_reblock: &crossbeam_channel::Receiver<
        raptorq::EncodingPacket,
    >,
    #[cfg(feature = "receive-mmsg")] for_reblock: &crossbeam_channel::Receiver<
        Vec<raptorq::EncodingPacket>,
    >,
) -> Result<(), crate::Error> {
    let min_nb_packets = usize::try_from(receiver.raptorq.min_nb_packets())
        .map_err(|e| crate::Error::Internal(format!("min_nb_packets: {e}")))?;
    let nb_packets = usize::try_from(receiver.raptorq.nb_packets())
        .map_err(|e| crate::Error::Internal(format!("nb_packets: {e}")))?;

    let mut blocks: [_; u8::MAX as usize + 1] = array::from_fn(|_| Block {
        ignore: true,
        packets: Vec::with_capacity(nb_packets),
    });

    let mut cur_id: u8 = 0;

    let mut reset = true;

    loop {
        let packets = match for_reblock.recv_timeout(receiver.config.reset_timeout) {
            Err(crossbeam_channel::RecvTimeoutError::Timeout) => {
                if !reset {
                    reset = true;

                    let prev = cur_id.wrapping_sub(1);
                    while cur_id != prev {
                        let nb_packets = blocks[cur_id as usize].packets.len();
                        if 0 < nb_packets {
                            if nb_packets < min_nb_packets {
                                log::warn!(
                                    "block {cur_id} is incomplete ({nb_packets} packets) after reset timeout, forcibly send to decode"
                                );
                                #[cfg(feature = "prometheus")]
                                metrics::counter!("lidi_receive_blocks_lost").increment(1);
                            }
                            let _ = send_to_decode(receiver, cur_id, &mut blocks)?;
                        }
                        cur_id = cur_id.wrapping_add(1);
                    }
                }

                continue;
            }
            Err(e) => return Err(crate::Error::from(e)),
            Ok(packets) => {
                #[cfg(not(feature = "receive-mmsg"))]
                {
                    [packets]
                }
                #[cfg(feature = "receive-mmsg")]
                packets
            }
        };

        if reset {
            reset = false;

            for block in &mut blocks {
                block.ignore = true;
                block.packets.clear();
            }

            let first_packet = &packets[0];

            cur_id = first_packet.payload_id().source_block_number();

            let mut id = cur_id;
            let last = id.wrapping_add(WINDOW_WIDTH);
            while id != last {
                blocks[id as usize].ignore = false;
                id = id.wrapping_add(1);
            }
        }

        let mut fast_track = false;

        let block_id_for_fast_track = cur_id.wrapping_add(WINDOW_WIDTH);

        for packet in packets {
            let id = packet.payload_id().source_block_number();

            if id == block_id_for_fast_track {
                fast_track = true;
                blocks[id as usize].ignore = false;
            }

            if blocks[id as usize].ignore {
                #[cfg(feature = "prometheus")]
                metrics::counter!("lidi_receive_packets_ignored").increment(1);
            } else {
                blocks[id as usize].packets.push(packet);
            }
        }

        if fast_track {
            log::warn!("probable network interrupt, fast track first block");
            let _ = send_to_decode(receiver, cur_id, &mut blocks)?;
            cur_id = cur_id.wrapping_add(1);
        }

        while blocks[cur_id as usize].packets.len() >= min_nb_packets {
            reset = send_to_decode(receiver, cur_id, &mut blocks)?;
            cur_id = cur_id.wrapping_add(1);
        }
    }
}
