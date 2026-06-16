//! Worker that writes decoded and reordered messages to client

use lidi_command_utils::config;
use lidi_protocol as protocol;
use std::{io::Write, os::fd::AsRawFd};

pub fn start<C, ClientNew, ClientEnd, E>(
    receiver: &crate::Receiver<ClientNew, ClientEnd>,
    endpoint_id: protocol::EndpointId,
    endpoint: &config::Endpoint,
    client_id: protocol::ClientId,
    for_client: &crossbeam_channel::Receiver<protocol::Block>,
) -> Result<(), crate::Error>
where
    C: Write + AsRawFd,
    ClientNew: Send + Sync + Fn(&config::Endpoint, protocol::ClientId) -> Result<C, E>,
    ClientEnd: Send + Sync + Fn(C, bool),
    E: Into<crate::Error>,
{
    let endpoint_options = endpoint.options();

    log::info!(
        "client {client_id:x}: starting transfer to endpoint {endpoint_id} ({endpoint_options})"
    );

    let mut client = (receiver.client_new)(endpoint, client_id).map_err(Into::into)?;

    let mut transmitted = 0;

    loop {
        let block = for_client.recv()?;

        let payload = block.payload();

        log::trace!("client {client_id:x}: payload {} bytes", payload.len());

        match block.block_type()? {
            protocol::BlockType::Data => {
                transmitted += payload.len();

                client.write_all(payload)?;
                if endpoint_options.flush {
                    client.flush()?;
                }
            }
            protocol::BlockType::End => {
                transmitted += payload.len();

                client.write_all(payload)?;
                client.flush()?;

                log::info!(
                    "client {client_id:x}: finished transfer, {transmitted} bytes transmitted"
                );
                (receiver.client_end)(client, true);
                break;
            }
            protocol::BlockType::Abort => {
                log::warn!("client {client_id:x}: aborting transfer");
                (receiver.client_end)(client, false);
                break;
            }
            protocol::BlockType::Start | protocol::BlockType::Heartbeat => (),
        }
    }

    Ok(())
}
