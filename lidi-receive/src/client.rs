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

    loop {
        let block = for_client.recv()?;

        let payload = block.payload();

        match block.block_type()? {
            protocol::BlockType::Data => {
                client.write_all(payload)?;
                if endpoint_options.flush {
                    client.flush()?;
                }
            }
            protocol::BlockType::End => {
                client.write_all(payload)?;
                client.flush()?;
                (receiver.client_end)(client, true);
                break;
            }
            protocol::BlockType::Abort => {
                (receiver.client_end)(client, false);
                break;
            }
            protocol::BlockType::Start | protocol::BlockType::Heartbeat => (),
        }
    }

    Ok(())
}
