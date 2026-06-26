//! Worker that writes decoded and reordered messages to client

use crate::ClientLifecycle;
use lidi_command_utils::config;
use lidi_protocol as protocol;
use std::io::Write;

pub fn start<Lifecycle>(
    receiver: &crate::Receiver<Lifecycle>,
    endpoint_id: protocol::EndpointId,
    endpoint: &config::Endpoint,
    client_id: protocol::ClientId,
    for_client: &crossbeam_channel::Receiver<protocol::Block>,
) -> Result<(), crate::Error>
where
    Lifecycle: ClientLifecycle,
{
    let endpoint_options = endpoint.options();

    log::info!(
        "client {client_id:x}: starting transfer to endpoint {endpoint_id} ({endpoint_options})"
    );

    let mut client = receiver.client_lifecycle.start(endpoint, client_id)?;

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
                if let Err(e) = receiver.client_lifecycle.end(client, true) {
                    log::error!("client {client_id:x}: {e}");
                }
                break;
            }
            protocol::BlockType::Abort => {
                if let Err(e) = receiver.client_lifecycle.end(client, false) {
                    log::error!("client {client_id:x}: {e}");
                }
                break;
            }
            protocol::BlockType::Start | protocol::BlockType::Heartbeat => (),
        }
    }

    Ok(())
}
