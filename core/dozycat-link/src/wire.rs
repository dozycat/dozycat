//! Length-delimited adapter for an ordered byte stream (e.g. a LAN TCP socket).
//! The caller MUST set finite read/write deadlines before passing a network socket.
use crate::{Error, Result, MAX_PLAINTEXT};
use std::io::{Read, Write};
pub fn read_frame(stream: &mut impl Read) -> Result<Vec<u8>> {
    let mut length = [0; 2];
    stream.read_exact(&mut length).map_err(|_| Error::Frame)?;
    let length = u16::from_be_bytes(length) as usize;
    if length == 0 || length > MAX_PLAINTEXT + 16 {
        return Err(Error::Frame);
    }
    let mut frame = vec![0; length];
    stream.read_exact(&mut frame).map_err(|_| Error::Frame)?;
    Ok(frame)
}
pub fn write_frame(stream: &mut impl Write, frame: &[u8]) -> Result<()> {
    if frame.is_empty() || frame.len() > MAX_PLAINTEXT + 16 {
        return Err(Error::Frame);
    }
    stream
        .write_all(&(frame.len() as u16).to_be_bytes())
        .map_err(|_| Error::Frame)?;
    stream.write_all(frame).map_err(|_| Error::Frame)?;
    stream.flush().map_err(|_| Error::Frame)?;
    Ok(())
}
