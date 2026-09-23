//! Native Swift/Kotlin boundary. These APIs are NOT to be exported directly to JS.
//! Identity and binding bytes must go only into platform protected storage.
use crate::*;
use std::sync::{Arc, Mutex};
#[derive(Debug, thiserror::Error, uniffi::Error)]
#[error("secure link operation rejected")]
pub enum LinkError {
    Rejected,
}
impl From<Error> for LinkError {
    fn from(_: Error) -> Self {
        Self::Rejected
    }
}
type FfiResult<T> = std::result::Result<T, LinkError>;
fn fixed<const N: usize>(value: &[u8]) -> FfiResult<[u8; N]> {
    value.try_into().map_err(|_| LinkError::Rejected)
}
fn lock<T>(m: &Mutex<T>) -> FfiResult<std::sync::MutexGuard<'_, T>> {
    m.lock().map_err(|_| LinkError::Rejected)
}

#[derive(uniffi::Object)]
pub struct LinkIdentity {
    inner: Identity,
}
#[uniffi::export]
impl LinkIdentity {
    #[uniffi::constructor]
    pub fn generate() -> FfiResult<Arc<Self>> {
        Ok(Arc::new(Self {
            inner: Identity::generate()?,
        }))
    }
    #[uniffi::constructor]
    pub fn restore(private_key: Vec<u8>) -> FfiResult<Arc<Self>> {
        let private_key = Zeroizing::new(private_key);
        let key = Zeroizing::new(fixed(&private_key)?);
        Ok(Arc::new(Self {
            inner: Identity::restore(&key)?,
        }))
    }
    pub fn public_key(&self) -> Vec<u8> {
        self.inner.public_key().to_vec()
    }
    pub fn private_key_for_native_storage(&self) -> Vec<u8> {
        self.inner.private_key_for_storage().to_vec()
    }
    pub fn invitation(&self) -> FfiResult<Arc<LinkInvitation>> {
        Ok(Arc::new(LinkInvitation {
            inner: Mutex::new(Invitation::new()?),
        }))
    }
    pub fn pair(
        &self,
        desktop: Vec<u8>,
        room: Vec<u8>,
        secret: Vec<u8>,
    ) -> FfiResult<Arc<LinkHandshake>> {
        let secret = Zeroizing::new(secret);
        let psk = Zeroizing::new(fixed(&secret)?);
        Ok(Arc::new(LinkHandshake {
            inner: Mutex::new(Some(Handshake::pair(
                &self.inner,
                fixed(&desktop)?,
                fixed(&room)?,
                &psk,
            )?)),
        }))
    }
    pub fn reconnect(
        &self,
        peer: Arc<LinkPeer>,
        initiator: bool,
        room: Vec<u8>,
    ) -> FfiResult<Arc<LinkHandshake>> {
        Ok(Arc::new(LinkHandshake {
            inner: Mutex::new(Some(Handshake::reconnect(
                &self.inner,
                &*lock(&peer.inner)?,
                initiator,
                fixed(&room)?,
            )?)),
        }))
    }
}
#[derive(uniffi::Object)]
pub struct LinkInvitation {
    inner: Mutex<Invitation>,
}
#[uniffi::export]
impl LinkInvitation {
    pub fn room(&self) -> FfiResult<Vec<u8>> {
        Ok(lock(&self.inner)?.room.to_vec())
    }
    pub fn secret_for_qr(&self) -> FfiResult<Vec<u8>> {
        Ok(lock(&self.inner)?.qr_secret()?.to_vec())
    }
    pub fn accept(&self, identity: Arc<LinkIdentity>) -> FfiResult<Arc<LinkHandshake>> {
        Ok(Arc::new(LinkHandshake {
            inner: Mutex::new(Some(lock(&self.inner)?.accept(&identity.inner)?)),
        }))
    }
    pub fn cancel(&self) -> FfiResult<()> {
        lock(&self.inner)?.cancel();
        Ok(())
    }
}
#[derive(uniffi::Object)]
pub struct LinkHandshake {
    inner: Mutex<Option<Handshake>>,
}
#[uniffi::export]
impl LinkHandshake {
    pub fn write(&self) -> FfiResult<Vec<u8>> {
        Ok(lock(&self.inner)?
            .as_mut()
            .ok_or(LinkError::Rejected)?
            .write()?)
    }
    pub fn read(&self, frame: Vec<u8>) -> FfiResult<()> {
        Ok(lock(&self.inner)?
            .as_mut()
            .ok_or(LinkError::Rejected)?
            .read(&frame)?)
    }
    pub fn finish(&self) -> FfiResult<Arc<LinkSession>> {
        Ok(Arc::new(LinkSession {
            inner: Mutex::new(
                lock(&self.inner)?
                    .take()
                    .ok_or(LinkError::Rejected)?
                    .finish()?,
            ),
        }))
    }
}
#[derive(uniffi::Object)]
pub struct LinkPeer {
    inner: Mutex<Peer>,
}
#[uniffi::export]
impl LinkPeer {
    /// Decode only from trusted, OS-protected *active* ACL storage, never from a network frame.
    #[uniffi::constructor]
    pub fn from_native_storage(bytes: Vec<u8>) -> FfiResult<Arc<Self>> {
        let bytes = Zeroizing::new(bytes);
        if bytes.len() != 99 || bytes[0] != 1 || bytes[97] != SCOPE_MOMENTS_ENERGY || bytes[98] > 1
        {
            return Err(LinkError::Rejected);
        }
        Ok(Arc::new(Self {
            inner: Mutex::new(Peer {
                public_key: fixed(&bytes[1..33])?,
                pair_id: fixed(&bytes[33..49])?,
                discovery_secret: fixed(&bytes[49..81])?,
                workspace: fixed(&bytes[81..97])?,
                scope: bytes[97],
                revoked: bytes[98] == 1,
            }),
        }))
    }
    pub fn bytes_for_native_storage(&self) -> FfiResult<Vec<u8>> {
        let p = lock(&self.inner)?;
        let mut bytes = vec![1];
        bytes.extend_from_slice(&p.public_key);
        bytes.extend_from_slice(&p.pair_id);
        bytes.extend_from_slice(&p.discovery_secret);
        bytes.extend_from_slice(&p.workspace);
        bytes.push(p.scope);
        bytes.push(u8::from(p.revoked));
        Ok(bytes)
    }
    pub fn public_key(&self) -> FfiResult<Vec<u8>> {
        Ok(lock(&self.inner)?.public_key.to_vec())
    }
    pub fn discovery_room(&self, unix_seconds: u64) -> FfiResult<Vec<u8>> {
        Ok(lock(&self.inner)?.discovery_room(unix_seconds)?.to_vec())
    }
    pub fn revoke(&self) -> FfiResult<()> {
        lock(&self.inner)?.revoke();
        Ok(())
    }
}
#[derive(uniffi::Enum)]
pub enum LinkEvent {
    Approved,
    BindingOffered,
    Persisted,
    Data { bytes: Vec<u8> },
}
#[derive(uniffi::Object)]
pub struct LinkSession {
    inner: Mutex<Session>,
}
#[uniffi::export]
impl LinkSession {
    pub fn fingerprint(&self) -> FfiResult<String> {
        Ok(lock(&self.inner)?.fingerprint())
    }
    pub fn peer_key(&self) -> FfiResult<Vec<u8>> {
        Ok(lock(&self.inner)?.peer_key().to_vec())
    }
    pub fn approve(&self) -> FfiResult<Vec<u8>> {
        Ok(lock(&self.inner)?.approve()?)
    }
    pub fn offer_binding(&self, workspace: Vec<u8>) -> FfiResult<Vec<u8>> {
        Ok(lock(&self.inner)?.offer_binding(fixed(&workspace)?)?)
    }
    pub fn pending_peer(&self) -> FfiResult<Arc<LinkPeer>> {
        Ok(Arc::new(LinkPeer {
            inner: Mutex::new(lock(&self.inner)?.pending_peer()?),
        }))
    }
    pub fn acknowledge_persisted(&self) -> FfiResult<Vec<u8>> {
        Ok(lock(&self.inner)?.acknowledge_persisted()?)
    }
    pub fn activate_after_acl_commit(&self) -> FfiResult<()> {
        Ok(lock(&self.inner)?.activate_after_acl_commit()?)
    }
    pub fn authorize_reconnect(&self, peer: Arc<LinkPeer>) -> FfiResult<()> {
        Ok(lock(&self.inner)?.authorize_reconnect(&*lock(&peer.inner)?)?)
    }
    pub fn send_data(&self, workspace: Vec<u8>, payload: Vec<u8>) -> FfiResult<Vec<u8>> {
        Ok(lock(&self.inner)?.send_data(fixed(&workspace)?, &payload)?)
    }
    pub fn receive(&self, ciphertext: Vec<u8>) -> FfiResult<LinkEvent> {
        Ok(match lock(&self.inner)?.receive(&ciphertext)? {
            Event::Approved => LinkEvent::Approved,
            Event::BindingOffered => LinkEvent::BindingOffered,
            Event::Persisted => LinkEvent::Persisted,
            Event::Data(bytes) => LinkEvent::Data { bytes },
        })
    }
    pub fn close(&self) -> FfiResult<()> {
        lock(&self.inner)?.close();
        Ok(())
    }
}
