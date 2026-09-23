use dozycat_link::*;

fn pending() -> (Identity, Identity, Session, Session) {
    let phone = Identity::generate().unwrap();
    let desktop = Identity::generate().unwrap();
    let mut invite = Invitation::new().unwrap();
    let psk = invite.qr_secret().unwrap();
    let mut p = Handshake::pair(&phone, desktop.public_key(), invite.room, &psk).unwrap();
    let mut d = invite.accept(&desktop).unwrap();
    d.read(&p.write().unwrap()).unwrap();
    p.read(&d.write().unwrap()).unwrap();
    (phone, desktop, p.finish().unwrap(), d.finish().unwrap())
}
fn paired() -> (Identity, Identity, Session, Session, Peer, Peer) {
    let (pi, di, mut p, mut d) = pending();
    d.receive(&p.approve().unwrap()).unwrap();
    p.receive(&d.approve().unwrap()).unwrap();
    p.receive(&d.offer_binding([7; 16]).unwrap()).unwrap();
    let pp = p.pending_peer().unwrap();
    let dp = d.pending_peer().unwrap();
    d.receive(&p.acknowledge_persisted().unwrap()).unwrap();
    p.receive(&d.acknowledge_persisted().unwrap()).unwrap();
    p.activate_after_acl_commit().unwrap();
    d.activate_after_acl_commit().unwrap();
    (pi, di, p, d, pp, dp)
}
#[test]
fn full_pairing_requires_both_approvals_and_both_durable_acks() {
    let (_, _, mut p, mut d) = pending();
    assert_eq!(p.fingerprint(), d.fingerprint());
    assert!(p.send_data([7; 16], b"private").is_err());
    assert!(d.offer_binding([7; 16]).is_err());
    assert!(matches!(
        d.receive(&p.approve().unwrap()).unwrap(),
        Event::Approved
    ));
    assert!(d.offer_binding([7; 16]).is_err());
    p.receive(&d.approve().unwrap()).unwrap();
    p.receive(&d.offer_binding([7; 16]).unwrap()).unwrap();
    assert!(p.activate_after_acl_commit().is_err());
    d.receive(&p.acknowledge_persisted().unwrap()).unwrap();
    assert!(p.activate_after_acl_commit().is_err());
    p.receive(&d.acknowledge_persisted().unwrap()).unwrap();
    p.activate_after_acl_commit().unwrap();
    d.activate_after_acl_commit().unwrap();
    let ciphertext = p.send_data([7; 16], b"private moment").unwrap();
    assert!(!ciphertext.windows(14).any(|w| w == b"private moment"));
    match d.receive(&ciphertext).unwrap() {
        Event::Data(data) => assert_eq!(data, b"private moment"),
        _ => panic!(),
    };
}
#[test]
fn invitation_is_one_candidate_only_and_cancelled_invites_fail() {
    let desktop = Identity::generate().unwrap();
    let mut invite = Invitation::new().unwrap();
    invite.accept(&desktop).unwrap();
    assert!(invite.accept(&desktop).is_err());
    assert!(invite.qr_secret().is_err());
    let mut invite = Invitation::new().unwrap();
    invite.cancel();
    assert!(invite.accept(&desktop).is_err());
}
#[test]
fn substituted_desktop_key_and_room_fail_authentication() {
    for wrong_room in [false, true] {
        let phone = Identity::generate().unwrap();
        let desktop = Identity::generate().unwrap();
        let other = Identity::generate().unwrap();
        let mut invite = Invitation::new().unwrap();
        let psk = invite.qr_secret().unwrap();
        let mut p = Handshake::pair(
            &phone,
            if wrong_room {
                desktop.public_key()
            } else {
                other.public_key()
            },
            if wrong_room { [0; 16] } else { invite.room },
            &psk,
        )
        .unwrap();
        let mut d = invite.accept(&desktop).unwrap();
        assert!(d.read(&p.write().unwrap()).is_err());
        assert!(d.write().is_err());
    }
}
#[test]
fn wrong_psk_cannot_finish_handshake() {
    let phone = Identity::generate().unwrap();
    let desktop = Identity::generate().unwrap();
    let mut invite = Invitation::new().unwrap();
    let mut p = Handshake::pair(&phone, desktop.public_key(), invite.room, &[0; 32]).unwrap();
    let mut d = invite.accept(&desktop).unwrap();
    d.read(&p.write().unwrap()).unwrap();
    assert!(p.read(&d.write().unwrap()).is_err());
    assert!(p.finish().is_err());
}
#[test]
fn tampering_and_replay_close_the_session_permanently() {
    for tamper in [true, false] {
        let (_, _, mut p, mut d, _, _) = paired();
        let mut frame = p.send_data([7; 16], b"hello").unwrap();
        if tamper {
            frame[0] ^= 1;
        } else {
            d.receive(&frame).unwrap();
        }
        assert!(d.receive(&frame).is_err());
        assert!(d.receive(&p.send_data([7; 16], b"next").unwrap()).is_err());
    }
}
#[test]
fn scope_and_workspace_are_enforced_and_oversized_data_is_rejected() {
    let (_, _, mut p, _, _, _) = paired();
    assert!(p.send_data([9; 16], b"x").is_err());
    assert!(p.send_data([7; 16], &vec![0; MAX_PLAINTEXT]).is_err());
    p.close();
    assert!(p.send_data([7; 16], b"x").is_err());
}
#[test]
fn reconnect_authenticates_both_keys_and_derives_a_fresh_session() {
    let (pi, di, _, _, pp, dp) = paired();
    assert_eq!(
        pp.discovery_room(1000).unwrap(),
        dp.discovery_room(1000).unwrap()
    );
    assert_ne!(
        pp.discovery_room(1000).unwrap(),
        pp.discovery_room(1400).unwrap()
    );
    let mut ciphertexts = vec![];
    for _ in 0..2 {
        let room = pp.discovery_room(1000).unwrap();
        let mut p = Handshake::reconnect(&pi, &pp, true, room).unwrap();
        let mut d = Handshake::reconnect(&di, &dp, false, room).unwrap();
        d.read(&p.write().unwrap()).unwrap();
        p.read(&d.write().unwrap()).unwrap();
        let mut p = p.finish().unwrap();
        let mut d = d.finish().unwrap();
        assert!(p.send_data([7; 16], b"same").is_err());
        p.authorize_reconnect(&pp).unwrap();
        d.authorize_reconnect(&dp).unwrap();
        let frame = p.send_data([7; 16], b"same").unwrap();
        d.receive(&frame).unwrap();
        ciphertexts.push(frame);
    }
    assert_ne!(ciphertexts[0], ciphertexts[1]);
    let mut revoked = dp.clone();
    revoked.revoke();
    assert!(Handshake::reconnect(&di, &revoked, false, [0; 16]).is_err());
    assert!(revoked.discovery_room(1000).is_err());
}
#[test]
fn wrong_phone_is_not_authorized_by_reconnect() {
    let (_, di, _, _, pp, dp) = paired();
    let imposter = Identity::generate().unwrap();
    let mut p = Handshake::reconnect(&imposter, &pp, true, [0; 16]).unwrap();
    let mut d = Handshake::reconnect(&di, &dp, false, [0; 16]).unwrap();
    d.read(&p.write().unwrap()).unwrap();
    p.read(&d.write().unwrap()).unwrap();
    assert!(d.finish().is_err());
}
#[test]
fn pairing_cannot_bypass_confirmation_via_reconnect_api() {
    let (_, _, mut p, mut d) = pending();
    d.receive(&p.approve().unwrap()).unwrap();
    p.receive(&d.approve().unwrap()).unwrap();
    p.receive(&d.offer_binding([7; 16]).unwrap()).unwrap();
    let peer = p.pending_peer().unwrap();
    assert!(p.authorize_reconnect(&peer).is_err());
    assert!(p.send_data([7; 16], b"secret").is_err());
}
#[test]
fn real_loro_delta_survives_encrypted_transfer_and_duplicate_import() {
    use dozycat_core::{Category, LoroStore, Memory};
    let temp = tempfile::tempdir().unwrap();
    let a = LoroStore::open(&temp.path().join("phone.db")).unwrap();
    let b = LoroStore::open(&temp.path().join("desktop.db")).unwrap();
    a.add(&Memory {
        id: "phone-test".into(),
        at_ms: 1000,
        text: "今天的晚霞很好看".into(),
        note: None,
        categories: vec![Category::Happy],
        tombstone: false,
    })
    .unwrap();
    let (_, _, mut p, mut d, _, _) = paired();
    let delta = a.export_updates(&b.version()).unwrap();
    let frame = p.send_data([7; 16], &delta).unwrap();
    let Event::Data(data) = d.receive(&frame).unwrap() else {
        panic!()
    };
    b.import_updates(&data).unwrap();
    b.import_updates(&data).unwrap();
    assert_eq!(b.timeline(10).len(), 1);
    assert_eq!(b.timeline(10)[0].text, "今天的晚霞很好看");
    drop(b);
    let b = LoroStore::open(&temp.path().join("desktop.db")).unwrap();
    assert_eq!(b.timeline(10).len(), 1);
}

#[test]
fn large_delta_uses_bounded_authenticated_chunks() {
    let (_, _, mut p, mut d, _, _) = paired();
    let payload = vec![73; 200_000];
    let frames = transfer::chunks([6; 16], &payload).unwrap();
    assert!(frames.len() > 1);
    let mut receiver = transfer::Receiver::default();
    let mut result = None;
    for frame in frames {
        let encrypted = p.send_data([7; 16], &frame).unwrap();
        let Event::Data(clear) = d.receive(&encrypted).unwrap() else {
            panic!()
        };
        result = receiver.push(&clear).unwrap();
    }
    assert_eq!(result.unwrap(), payload);
}
#[test]
fn reordered_mixed_truncated_and_overbudget_transfers_are_rejected() {
    let frames = transfer::chunks([1; 16], &vec![9; 100_000]).unwrap();
    let other = transfer::chunks([2; 16], &vec![8; 100_000]).unwrap();
    let mut receiver = transfer::Receiver::default();
    assert!(receiver.push(&frames[1]).is_err());
    receiver.push(&frames[0]).unwrap();
    assert!(receiver.push(&other[1]).is_err());
    assert!(receiver.push(&frames[1]).is_err());
    assert!(receiver.push(&frames[0][..100]).is_err());
    let mut oversized = frames[0].clone();
    oversized[16..20].copy_from_slice(&u32::MAX.to_be_bytes());
    assert!(receiver.push(&oversized).is_err());
}
