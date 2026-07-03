//! Worker that acquires multiplex access and then becomes a `crate::receive::client` worker

use crate::{ClientLifecycle, client, client_reorder};
use lidi_protocol as protocol;
use std::thread;

pub fn start<Lifecycle>(
    receiver: &crate::Receiver<Lifecycle>,
    thread_number: u32,
) -> Result<(), crate::Error>
where
    Lifecycle: ClientLifecycle,
{
    loop {
        let (endpoint_id, client_id, recvq) = receiver.for_clients.recv()?;

        let Some(endpoint) = receiver.config.to.get(usize::from(endpoint_id.value())) else {
            log::error!("{}", protocol::Error::InvalidEndpoint(endpoint_id,));
            continue;
        };

        let mut failed = false;

        thread::scope(|scope| {
            let (to_client, for_client) = recvq
                .capacity()
                .map_or_else(crossbeam_channel::unbounded, crossbeam_channel::bounded);

            thread::Builder::new()
                .name(format!("reorder_{thread_number}"))
                .spawn_scoped(scope, move || {
                    if let Err(e) = client_reorder::start(
                        receiver,
                        thread_number,
                        client_id,
                        &recvq,
                        &to_client,
                        endpoint.options().hash,
                    ) {
                        log::error!("client {client_id:x} reorder error: {e}");
                    }

                    let _ = recvq;
                    let _ = to_client;
                })
                .unwrap();

            let client_res = client::start(receiver, endpoint_id, endpoint, client_id, &for_client);

            if let Err(e) = client_res {
                log::error!("client {client_id:x}: {e}");
                failed = true;
            }

            let _ = for_client;
        });

        receiver.active_transfers.remove(&client_id);

        if failed {
            receiver.failed_transfers.insert(client_id);
        }

        thread::yield_now();
    }
}
