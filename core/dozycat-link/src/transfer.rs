//! Bounded, ordered delta assembly. Only feed plaintext returned by an ACTIVE Session.
use crate::{Error, Result};
use std::time::{Duration, Instant};
use zeroize::Zeroizing;
pub const CHUNK: usize = 48 * 1024;
pub const MAX_TRANSFER: usize = 32 * 1024 * 1024;
const HEADER: usize = 24;

pub fn chunks(id: [u8; 16], bytes: &[u8]) -> Result<Vec<Vec<u8>>> {
    if bytes.is_empty() || bytes.len() > MAX_TRANSFER {
        return Err(Error::Frame);
    }
    Ok(bytes
        .chunks(CHUNK)
        .enumerate()
        .map(|(index, payload)| {
            let mut frame = Vec::with_capacity(HEADER + payload.len());
            frame.extend_from_slice(&id);
            frame.extend_from_slice(&(bytes.len() as u32).to_be_bytes());
            frame.extend_from_slice(&(index as u32).to_be_bytes());
            frame.extend_from_slice(payload);
            frame
        })
        .collect())
}

/// One incomplete transfer per session; no attacker-controlled preallocation.
#[derive(Default)]
pub struct Receiver {
    pending: Option<Pending>,
}
struct Pending {
    id: [u8; 16],
    total: usize,
    next: usize,
    started: Instant,
    bytes: Zeroizing<Vec<u8>>,
}
impl Receiver {
    pub fn push(&mut self, frame: &[u8]) -> Result<Option<Vec<u8>>> {
        let pending = self.pending.take(); // malformed frames discard all partial plaintext
        if frame.len() <= HEADER || frame.len() > HEADER + CHUNK {
            return Err(Error::Frame);
        }
        let id: [u8; 16] = frame[..16].try_into().map_err(|_| Error::Frame)?;
        let total =
            u32::from_be_bytes(frame[16..20].try_into().map_err(|_| Error::Frame)?) as usize;
        let index =
            u32::from_be_bytes(frame[20..24].try_into().map_err(|_| Error::Frame)?) as usize;
        if total == 0 || total > MAX_TRANSFER {
            return Err(Error::Frame);
        }
        let mut pending = match pending {
            Some(p)
                if p.id == id
                    && p.total == total
                    && p.next == index
                    && p.started.elapsed() < Duration::from_secs(30) =>
            {
                p
            }
            None if index == 0 => Pending {
                id,
                total,
                next: 0,
                started: Instant::now(),
                bytes: Zeroizing::new(Vec::new()),
            },
            _ => return Err(Error::Frame),
        };
        let remaining = pending.total - pending.bytes.len();
        if frame.len() - HEADER != remaining.min(CHUNK) {
            return Err(Error::Frame);
        }
        pending.bytes.extend_from_slice(&frame[HEADER..]);
        pending.next += 1;
        if pending.bytes.len() == total {
            Ok(Some(std::mem::take(&mut *pending.bytes)))
        } else {
            self.pending = Some(pending);
            Ok(None)
        }
    }
    pub fn clear(&mut self) {
        self.pending = None;
    }
}
