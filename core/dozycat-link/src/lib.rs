//! Transport-independent Noise sessions. Use only over a reliable ordered channel.
//! The platform owns OS-protected identity storage and durable ACL transactions.
use hmac::{Hmac, Mac};
use sha2::{Digest, Sha256};
mod ffi;
pub mod transfer;
pub mod wire;
uniffi::setup_scaffolding!();
use std::time::{Duration, Instant};
use zeroize::{Zeroize, ZeroizeOnDrop, Zeroizing};

const PAIR: &str = "Noise_IKpsk2_25519_ChaChaPoly_SHA256";
const RECONNECT: &str = "Noise_IK_25519_ChaChaPoly_SHA256";
pub const MAX_PLAINTEXT: usize = 60_000;
pub const SCOPE_MOMENTS_ENERGY: u8 = 1;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("invalid protocol state")]
    State,
    #[error("authentication failed")]
    Authentication,
    #[error("invitation expired or consumed")]
    Invitation,
    #[error("invalid or oversized frame")]
    Frame,
    #[error("device is not authorized")]
    Unauthorized,
    #[error("cryptographic operation failed")]
    Crypto,
}
pub type Result<T> = std::result::Result<T, Error>;
fn random<const N: usize>() -> Result<[u8; N]> {
    let mut bytes = [0; N];
    getrandom::fill(&mut bytes).map_err(|_| Error::Crypto)?;
    Ok(bytes)
}

#[derive(Zeroize, ZeroizeOnDrop)]
pub struct Identity {
    private: [u8; 32],
    public: [u8; 32],
}
impl Identity {
    pub fn generate() -> Result<Self> {
        let pair = snow::Builder::new(PAIR.parse().map_err(|_| Error::Crypto)?)
            .generate_keypair()
            .map_err(|_| Error::Crypto)?;
        let private = Zeroizing::new(pair.private);
        Ok(Self {
            private: private.as_slice().try_into().map_err(|_| Error::Crypto)?,
            public: pair
                .public
                .as_slice()
                .try_into()
                .map_err(|_| Error::Crypto)?,
        })
    }
    pub fn restore(private: &[u8; 32]) -> Result<Self> {
        use snow::resolvers::CryptoResolver;
        let mut dh = snow::resolvers::DefaultResolver
            .resolve_dh(&snow::params::DHChoice::Curve25519)
            .ok_or(Error::Crypto)?;
        dh.set(private);
        Ok(Self {
            private: *private,
            public: dh.pubkey().try_into().map_err(|_| Error::Crypto)?,
        })
    }
    pub fn public_key(&self) -> [u8; 32] {
        self.public
    }
    /// For native OS-protected storage only. Never send this through JS or a network.
    pub fn private_key_for_storage(&self) -> Zeroizing<[u8; 32]> {
        Zeroizing::new(self.private)
    }
}

pub struct Invitation {
    pub room: [u8; 16],
    secret: Zeroizing<[u8; 32]>,
    expires: Instant,
    used: bool,
}
impl Invitation {
    pub fn new() -> Result<Self> {
        Ok(Self {
            room: random()?,
            secret: Zeroizing::new(random()?),
            expires: Instant::now() + Duration::from_secs(120),
            used: false,
        })
    }
    /// Only render into a local QR code. Never log or transmit via signaling.
    pub fn qr_secret(&self) -> Result<Zeroizing<[u8; 32]>> {
        self.check()?;
        Ok(Zeroizing::new(*self.secret))
    }
    fn check(&self) -> Result<()> {
        if self.used || Instant::now() >= self.expires {
            Err(Error::Invitation)
        } else {
            Ok(())
        }
    }
    /// Reserves the entire invitation for one candidate, including on authentication failure.
    /// Generate a fresh QR after a rejected/failed attempt; never reuse the PSK.
    pub fn accept(&mut self, identity: &Identity) -> Result<Handshake> {
        self.check()?;
        self.used = true;
        let result =
            Handshake::build(identity, false, None, Some(&self.secret), self.room).map(|mut h| {
                h.deadline = Some(self.expires);
                h
            });
        self.secret.zeroize();
        result
    }
    pub fn cancel(&mut self) {
        self.used = true;
        self.secret.zeroize();
    }
}

pub struct Handshake {
    inner: Option<snow::HandshakeState>,
    initiator: bool,
    expected: Option<[u8; 32]>,
    pairing: bool,
    deadline: Option<Instant>,
}
impl Handshake {
    pub fn pair(
        identity: &Identity,
        desktop: [u8; 32],
        room: [u8; 16],
        psk: &[u8; 32],
    ) -> Result<Self> {
        Self::build(identity, true, Some(desktop), Some(psk), room)
    }
    /// Caller must obtain this peer from its *active*, non-revoked durable ACL.
    pub fn reconnect(
        identity: &Identity,
        peer: &Peer,
        initiator: bool,
        room: [u8; 16],
    ) -> Result<Self> {
        if peer.revoked {
            return Err(Error::Unauthorized);
        }
        Self::build(identity, initiator, Some(peer.public_key), None, room)
    }
    fn build(
        identity: &Identity,
        initiator: bool,
        expected: Option<[u8; 32]>,
        psk: Option<&[u8; 32]>,
        room: [u8; 16],
    ) -> Result<Self> {
        let mut prologue = b"dozycat/link/v1/phone-initiator/desktop-responder/".to_vec();
        prologue.extend_from_slice(&room);
        let mut builder = snow::Builder::new(
            (if psk.is_some() { PAIR } else { RECONNECT })
                .parse()
                .map_err(|_| Error::Crypto)?,
        )
        .local_private_key(&identity.private)
        .map_err(|_| Error::Crypto)?
        .prologue(&prologue)
        .map_err(|_| Error::Crypto)?;
        if let Some(key) = expected.as_ref() {
            if initiator {
                builder = builder.remote_public_key(key).map_err(|_| Error::Crypto)?;
            }
        }
        if let Some(psk) = psk {
            builder = builder.psk(2, psk).map_err(|_| Error::Crypto)?;
        }
        let inner = if initiator {
            builder.build_initiator()
        } else {
            builder.build_responder()
        }
        .map_err(|_| Error::Crypto)?;
        Ok(Self {
            inner: Some(inner),
            initiator,
            expected,
            pairing: psk.is_some(),
            deadline: psk.map(|_| Instant::now() + Duration::from_secs(120)),
        })
    }
    pub fn write(&mut self) -> Result<Vec<u8>> {
        let mut inner = self.inner.take().ok_or(Error::State)?;
        if self.deadline.is_some_and(|d| Instant::now() >= d) {
            return Err(Error::Invitation);
        }
        let mut out = vec![0; 1024];
        let len = inner
            .write_message(&[], &mut out)
            .map_err(|_| Error::Authentication)?;
        out.truncate(len);
        self.inner = Some(inner);
        Ok(out)
    }
    pub fn read(&mut self, message: &[u8]) -> Result<()> {
        let mut inner = self.inner.take().ok_or(Error::State)?;
        if self.deadline.is_some_and(|d| Instant::now() >= d) {
            return Err(Error::Invitation);
        }
        if message.len() > 1024 {
            return Err(Error::Frame);
        }
        let mut payload = [0; 1024];
        let len = inner
            .read_message(message, &mut payload)
            .map_err(|_| Error::Authentication)?;
        if len != 0 {
            return Err(Error::Frame);
        } // no 0-RTT application payloads
        self.inner = Some(inner);
        Ok(())
    }
    pub fn finish(mut self) -> Result<Session> {
        let inner = self.inner.take().ok_or(Error::State)?;
        if self.deadline.is_some_and(|d| Instant::now() >= d) {
            return Err(Error::Invitation);
        }
        if !inner.is_handshake_finished() {
            return Err(Error::State);
        }
        let peer: [u8; 32] = inner
            .get_remote_static()
            .ok_or(Error::Authentication)?
            .try_into()
            .map_err(|_| Error::Authentication)?;
        if self.expected.is_some_and(|key| key != peer) {
            return Err(Error::Authentication);
        }
        let hash = inner
            .get_handshake_hash()
            .try_into()
            .map_err(|_| Error::Crypto)?;
        Ok(Session {
            transport: Some(inner.into_transport_mode().map_err(|_| Error::Crypto)?),
            initiator: self.initiator,
            peer,
            hash,
            local_approved: !self.pairing,
            remote_approved: !self.pairing,
            local_persisted: false,
            remote_persisted: false,
            binding: None,
            active: false,
            reconnect: !self.pairing,
            deadline: self.deadline,
        })
    }
}

/// Store atomically with the platform ACL, protected by Keychain/Keystore.
/// Not a CRDT entry: merging stale business data must never reinstate authorization.
#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct Peer {
    pub public_key: [u8; 32],
    pub pair_id: [u8; 16],
    pub discovery_secret: [u8; 32],
    pub workspace: [u8; 16],
    pub scope: u8,
    pub revoked: bool,
}
impl Peer {
    pub fn revoke(&mut self) {
        self.revoked = true;
        self.discovery_secret.zeroize();
    }
    pub fn discovery_room(&self, unix_seconds: u64) -> Result<[u8; 16]> {
        if self.revoked {
            return Err(Error::Unauthorized);
        }
        let mut key = Zeroizing::new([0; 32]);
        hkdf::Hkdf::<Sha256>::new(Some(&self.pair_id), &self.discovery_secret)
            .expand(b"dozycat/discovery/v1", key.as_mut())
            .map_err(|_| Error::Crypto)?;
        let mut mac = Hmac::<Sha256>::new_from_slice(key.as_ref()).map_err(|_| Error::Crypto)?;
        mac.update(b"dozycat/room/v1");
        mac.update(&(unix_seconds / 300).to_be_bytes());
        mac.finalize().into_bytes()[..16]
            .try_into()
            .map_err(|_| Error::Crypto)
    }
}

pub enum Event {
    Approved,
    BindingOffered,
    Persisted,
    Data(Vec<u8>),
}
pub struct Session {
    transport: Option<snow::TransportState>,
    initiator: bool,
    peer: [u8; 32],
    hash: [u8; 32],
    local_approved: bool,
    remote_approved: bool,
    local_persisted: bool,
    remote_persisted: bool,
    binding: Option<Peer>,
    active: bool,
    reconnect: bool,
    deadline: Option<Instant>,
}
impl Session {
    /// Full 128-bit visual comparison value, not a six-digit authentication secret.
    pub fn fingerprint(&self) -> String {
        let mut hash = Sha256::new();
        hash.update(b"dozycat/compare/v1");
        hash.update(self.hash);
        hash.finalize()[..16]
            .chunks(2)
            .map(|c| format!("{:02X}{:02X}", c[0], c[1]))
            .collect::<Vec<_>>()
            .join(" ")
    }
    pub fn peer_key(&self) -> [u8; 32] {
        self.peer
    }
    fn seal(&mut self, data: &[u8]) -> Result<Vec<u8>> {
        if self.deadline.is_some_and(|d| Instant::now() >= d) {
            self.close();
            return Err(Error::Invitation);
        }
        if data.len() > MAX_PLAINTEXT {
            return Err(Error::Frame);
        }
        let mut transport = self.transport.take().ok_or(Error::State)?;
        if self.deadline.is_some_and(|d| Instant::now() >= d) {
            return Err(Error::Invitation);
        }
        let mut out = vec![0; data.len() + 16];
        let len = transport
            .write_message(data, &mut out)
            .map_err(|_| Error::Crypto)?;
        out.truncate(len);
        self.transport = Some(transport);
        Ok(out)
    }
    pub fn approve(&mut self) -> Result<Vec<u8>> {
        if self.local_approved {
            return Err(Error::State);
        }
        let out = self.seal(&[1])?;
        self.local_approved = true;
        Ok(out)
    }
    /// Desktop chooses a workspace only after the user explicitly agrees to merge it.
    pub fn offer_binding(&mut self, workspace: [u8; 16]) -> Result<Vec<u8>> {
        if self.reconnect
            || self.initiator
            || !self.local_approved
            || !self.remote_approved
            || self.binding.is_some()
        {
            return Err(Error::State);
        }
        let binding = Peer {
            public_key: self.peer,
            pair_id: random()?,
            discovery_secret: random()?,
            workspace,
            scope: SCOPE_MOMENTS_ENERGY,
            revoked: false,
        };
        let mut plain = Zeroizing::new(vec![2]);
        plain.extend_from_slice(&binding.pair_id);
        plain.extend_from_slice(&binding.discovery_secret);
        plain.extend_from_slice(&workspace);
        plain.push(binding.scope);
        let out = self.seal(&plain)?;
        self.binding = Some(binding);
        Ok(out)
    }
    /// Persist as PENDING first. This record alone must never grant reconnection access.
    pub fn pending_peer(&self) -> Result<Peer> {
        self.binding.clone().ok_or(Error::State)
    }
    /// Call only after the pending peer has been durably written by the platform.
    pub fn acknowledge_persisted(&mut self) -> Result<Vec<u8>> {
        if self.reconnect || self.binding.is_none() || self.local_persisted {
            return Err(Error::State);
        }
        let out = self.seal(&[3])?;
        self.local_persisted = true;
        Ok(out)
    }
    /// After both persistence ACKs, atomically promote the ACL to ACTIVE, then call this.
    /// A crash before promotion requires a fresh pairing in v1 (fail closed, no auto-resume).
    pub fn activate_after_acl_commit(&mut self) -> Result<()> {
        if self.deadline.is_some_and(|d| Instant::now() >= d) {
            self.close();
            return Err(Error::Invitation);
        }
        if !self.local_persisted || !self.remote_persisted || self.transport.is_none() {
            return Err(Error::Unauthorized);
        }
        self.active = true;
        self.deadline = None;
        Ok(())
    }
    /// Reconnection also has no business payload until the full new handshake and ACL check.
    pub fn authorize_reconnect(&mut self, peer: &Peer) -> Result<()> {
        if self.transport.is_none()
            || !self.reconnect
            || !self.local_approved
            || !self.remote_approved
            || self.binding.is_some()
            || peer.revoked
            || peer.public_key != self.peer
        {
            return Err(Error::Unauthorized);
        }
        self.binding = Some(peer.clone());
        self.active = true;
        self.deadline = None;
        Ok(())
    }
    pub fn send_data(&mut self, workspace: [u8; 16], payload: &[u8]) -> Result<Vec<u8>> {
        if !self.active {
            return Err(Error::Unauthorized);
        }
        let binding = self.binding.as_ref().ok_or(Error::Unauthorized)?;
        if binding.workspace != workspace
            || binding.revoked
            || binding.scope != SCOPE_MOMENTS_ENERGY
        {
            return Err(Error::Unauthorized);
        }
        if payload.len() > MAX_PLAINTEXT - 18 {
            return Err(Error::Frame);
        }
        let mut frame = Zeroizing::new(vec![4]);
        frame.extend_from_slice(&workspace);
        frame.push(binding.scope);
        frame.extend_from_slice(payload);
        self.seal(&frame)
    }
    pub fn receive(&mut self, ciphertext: &[u8]) -> Result<Event> {
        let mut transport = self.transport.take().ok_or(Error::State)?;
        if self.deadline.is_some_and(|d| Instant::now() >= d) {
            return Err(Error::Invitation);
        }
        if ciphertext.len() > MAX_PLAINTEXT + 16 {
            return Err(Error::Frame);
        }
        let mut plain = Zeroizing::new(vec![0; MAX_PLAINTEXT]);
        let len = transport
            .read_message(ciphertext, &mut plain)
            .map_err(|_| Error::Authentication)?;
        let plain = &plain[..len];
        let event = match plain.first() {
            Some(1) if !self.reconnect && len == 1 && !self.remote_approved => {
                self.remote_approved = true;
                Event::Approved
            }
            Some(2)
                if !self.reconnect
                    && len == 66
                    && self.initiator
                    && self.local_approved
                    && self.remote_approved
                    && self.binding.is_none()
                    && plain[65] == SCOPE_MOMENTS_ENERGY =>
            {
                self.binding = Some(Peer {
                    public_key: self.peer,
                    pair_id: plain[1..17].try_into().unwrap(),
                    discovery_secret: plain[17..49].try_into().unwrap(),
                    workspace: plain[49..65].try_into().unwrap(),
                    scope: plain[65],
                    revoked: false,
                });
                Event::BindingOffered
            }
            Some(3)
                if !self.reconnect
                    && len == 1
                    && self.binding.is_some()
                    && !self.remote_persisted =>
            {
                self.remote_persisted = true;
                Event::Persisted
            }
            Some(4) if len >= 18 && self.active => {
                let binding = self.binding.as_ref().ok_or(Error::Unauthorized)?;
                if binding.revoked
                    || plain[1..17] != binding.workspace
                    || plain[17] != binding.scope
                {
                    return Err(Error::Unauthorized);
                }
                Event::Data(plain[18..].to_vec())
            }
            _ => return Err(Error::Unauthorized),
        };
        self.transport = Some(transport);
        Ok(event)
    }
    /// Called immediately on rejection, timeout, revocation, or channel termination.
    pub fn close(&mut self) {
        self.transport = None;
        self.binding = None;
        self.active = false;
    }
}

#[cfg(test)]
mod expiry_tests {
    use super::*;
    #[test]
    fn expired_invitation_cannot_create_a_handshake() {
        let identity = Identity::generate().unwrap();
        let mut invite = Invitation::new().unwrap();
        invite.expires = Instant::now();
        assert!(invite.accept(&identity).is_err());
        assert!(invite.qr_secret().is_err());
    }
    #[test]
    fn reserved_invitation_keeps_original_deadline() {
        let identity = Identity::generate().unwrap();
        let mut invite = Invitation::new().unwrap();
        let mut h = invite.accept(&identity).unwrap();
        h.deadline = Some(Instant::now());
        assert!(h.read(&[0; 32]).is_err());
        assert!(h.write().is_err());
    }
}
