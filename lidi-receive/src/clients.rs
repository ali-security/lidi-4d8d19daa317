//! Worker that acquires multiplex access and then becomes a `crate::receive::client` worker

use crate::{client, client_reorder};
use lidi_command_utils::config;
use lidi_protocol as protocol;
use std::{io::Write, os::fd::AsRawFd, thread};

pub fn start<C, ClientNew, ClientEnd, E>(
    receiver: &crate::Receiver<ClientNew, ClientEnd>,
    thread_number: u32,
) -> Result<(), crate::Error>
where
    C: Write + AsRawFd,
    ClientNew: Send + Sync + Fn(&config::Endpoint, protocol::ClientId) -> Result<C, E>,
    ClientEnd: Send + Sync + Fn(C, bool),
    E: Into<crate::Error>,
{
    loop {
        let (endpoint_id, client_id, recvq) = receiver.for_clients.recv()?;

        let Some(endpoint) = receiver.config.to.get(usize::from(endpoint_id.value())) else {
            log::error!("{}", protocol::Error::InvalidEndpoint(endpoint_id,));
            continue;
        };

        thread::scope(|scope| {
            let (to_client, for_client) = recvq
                .capacity()
                .map_or_else(crossbeam_channel::unbounded, crossbeam_channel::bounded);

            thread::Builder::new()
                .name(format!("client_{thread_number}_reorder"))
                .spawn_scoped(scope, move || {
                    if let Err(e) = client_reorder::start(
                        receiver,
                        thread_number,
                        client_id,
                        &recvq,
                        &to_client,
                        endpoint.options().hash,
                    ) {
                        log::error!("client reorder error {client_id:x}: {e}");
                    }

                    let _ = recvq;
                    let _ = to_client;
                })
                .unwrap();

            let client_res = client::start(receiver, endpoint_id, endpoint, client_id, &for_client);

            if let Err(e) = client_res {
                log::error!("client {client_id:x}: {e}");
            }

            let _ = for_client;
        });

        receiver.active_transfers.remove(&client_id);

        thread::yield_now();
    }
}
