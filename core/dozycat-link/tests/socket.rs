//! Real sockets, isolated identities and data. The approval calls emulate user actions
//! for this test only; applications must collect explicit confirmation on both devices.
use dozycat_link::*;
use std::net::{TcpListener, TcpStream};
use std::time::Duration;
fn deadlines(stream: &TcpStream) {
    stream
        .set_read_timeout(Some(Duration::from_secs(3)))
        .unwrap();
    stream
        .set_write_timeout(Some(Duration::from_secs(3)))
        .unwrap();
}
#[test]
fn two_threads_pair_and_transfer_over_real_tcp() {
    let desktop = Identity::generate().unwrap();
    let phone = Identity::generate().unwrap();
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let address = listener.local_addr().unwrap();
    let mut invite = Invitation::new().unwrap();
    let psk = invite.qr_secret().unwrap();
    let room = invite.room;
    let public = desktop.public_key();
    let responder = std::thread::spawn(move || {
        let (mut socket, _) = listener.accept().unwrap();
        deadlines(&socket);
        let mut h = invite.accept(&desktop).unwrap();
        h.read(&wire::read_frame(&mut socket).unwrap()).unwrap();
        wire::write_frame(&mut socket, &h.write().unwrap()).unwrap();
        let mut s = h.finish().unwrap();
        s.receive(&wire::read_frame(&mut socket).unwrap()).unwrap();
        wire::write_frame(&mut socket, &s.approve().unwrap()).unwrap();
        wire::write_frame(&mut socket, &s.offer_binding([7; 16]).unwrap()).unwrap();
        s.receive(&wire::read_frame(&mut socket).unwrap()).unwrap();
        wire::write_frame(&mut socket, &s.acknowledge_persisted().unwrap()).unwrap();
        s.activate_after_acl_commit().unwrap();
        let Event::Data(data) = s.receive(&wire::read_frame(&mut socket).unwrap()).unwrap() else {
            panic!()
        };
        assert_eq!(data, "测试小传".as_bytes());
        wire::write_frame(&mut socket, &s.send_data([7; 16], b"received").unwrap()).unwrap();
        s.fingerprint()
    });
    let mut socket = TcpStream::connect(address).unwrap();
    deadlines(&socket);
    let mut h = Handshake::pair(&phone, public, room, &psk).unwrap();
    wire::write_frame(&mut socket, &h.write().unwrap()).unwrap();
    h.read(&wire::read_frame(&mut socket).unwrap()).unwrap();
    let mut s = h.finish().unwrap();
    wire::write_frame(&mut socket, &s.approve().unwrap()).unwrap();
    s.receive(&wire::read_frame(&mut socket).unwrap()).unwrap();
    s.receive(&wire::read_frame(&mut socket).unwrap()).unwrap();
    wire::write_frame(&mut socket, &s.acknowledge_persisted().unwrap()).unwrap();
    s.receive(&wire::read_frame(&mut socket).unwrap()).unwrap();
    s.activate_after_acl_commit().unwrap();
    wire::write_frame(
        &mut socket,
        &s.send_data([7; 16], "测试小传".as_bytes()).unwrap(),
    )
    .unwrap();
    let Event::Data(reply) = s.receive(&wire::read_frame(&mut socket).unwrap()).unwrap() else {
        panic!()
    };
    assert_eq!(reply, b"received");
    assert_eq!(s.fingerprint(), responder.join().unwrap());
}
#[test]
fn truncated_or_oversized_network_frames_fail_before_allocation() {
    assert!(wire::read_frame(&mut &b"\0\x10short"[..]).is_err());
    assert!(wire::read_frame(&mut &b"\xff\xff"[..]).is_err());
    assert!(wire::read_frame(&mut &b"\0\0"[..]).is_err());
}
