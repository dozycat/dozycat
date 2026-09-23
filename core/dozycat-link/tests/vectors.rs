// Known-answer fixtures from Cacophony, distributed in snow 0.10.0 tests/vectors/cacophony.txt.
// https://github.com/mcginty/snow/blob/v0.10.0/tests/vectors/cacophony.txt
// Fixed ephemeral keys appear ONLY in this test; production always uses the OS CSPRNG.
fn hex(s: &str) -> Vec<u8> {
    s.as_bytes()
        .chunks(2)
        .map(|b| u8::from_str_radix(std::str::from_utf8(b).unwrap(), 16).unwrap())
        .collect()
}

#[test]
fn cacophony_0() {
    let is = hex("e61ef9919cde45dd5f82166404bd08e38bceb5dfdfded0a34c8df7ed542214d1");
    let ie = hex("893e28b9dc6ca8d611ab664754b8ceb7bac5117349a4439a6b0569da977c464a");
    let rs = hex("31e0303fd6418d2f8c0e78b91f22e8caed0fbe48656dcf4767e4834f701b8f62");
    let ds = hex("4a3acbfdb163dec651dfa3194dece676d437029c62a408b4c5ea9114246e4893");
    let de = hex("bbdb4cdbd309f1a1f2e1456967fe288cadd6f712d65dc7b7793d5e63da6b375b");
    let pro = hex("4a6f686e2047616c74");
    let mut ib = snow::Builder::new("Noise_IK_25519_ChaChaPoly_SHA256".parse().unwrap())
        .local_private_key(&is)
        .unwrap()
        .remote_public_key(&rs)
        .unwrap()
        .prologue(&pro)
        .unwrap()
        .fixed_ephemeral_key_for_testing_only(&ie);
    let mut db = snow::Builder::new("Noise_IK_25519_ChaChaPoly_SHA256".parse().unwrap())
        .local_private_key(&ds)
        .unwrap()
        .prologue(&pro)
        .unwrap()
        .fixed_ephemeral_key_for_testing_only(&de);
    let _ = (&mut ib, &mut db);
    let mut p = ib.build_initiator().unwrap();
    let mut d = db.build_responder().unwrap();
    let mut buf = [0; 1024];
    let mut clear = [0; 1024];
    let payload = hex("4c756477696720766f6e204d69736573");
    let n = p.write_message(&payload, &mut buf).unwrap();
    assert_eq!(&buf[..n],hex("ca35def5ae56cec33dc2036731ab14896bc4c75dbb07a61f879f8e3afa4c7944718da798efbcd91528520204f904b9bd6c7413dccdc214d951e15253e39987f18146e8cd0873654207148333479d4d16c289f0294b29960a72f48e0b7bba2e89083169825e59642148d492020664ccf7"));
    let n = d.read_message(&buf[..n], &mut clear).unwrap();
    assert_eq!(&clear[..n], payload);
    let payload = hex("4d757272617920526f746862617264");
    let n = d.write_message(&payload, &mut buf).unwrap();
    assert_eq!(&buf[..n],hex("95ebc60d2b1fa672c1f46a8aa265ef51bfe38e7ccb39ec5be34069f1448088435361e70b2ed446e6c9ec387d1d6b3b840f194e373979d241b203c4acafccf5"));
    let n = p.read_message(&buf[..n], &mut clear).unwrap();
    assert_eq!(&clear[..n], payload);
    assert_eq!(
        p.get_handshake_hash(),
        hex("0b0f68fb0c27e03ce9b97565995ed4838cc0581b762ef72b062f6a546419fad7")
    );
    assert_eq!(d.get_handshake_hash(), p.get_handshake_hash());
    let mut p = p.into_transport_mode().unwrap();
    let mut d = d.into_transport_mode().unwrap();
    let payload = hex("462e20412e20486179656b");
    let n = p.write_message(&payload, &mut buf).unwrap();
    assert_eq!(
        &buf[..n],
        hex("050e9f3c8fac16b68dbce8f8c4bfbf6617c897f9ada4aa29aa19c8")
    );
    let n = d.read_message(&buf[..n], &mut clear).unwrap();
    assert_eq!(&clear[..n], payload);
    let payload = hex("4361726c204d656e676572");
    let n = d.write_message(&payload, &mut buf).unwrap();
    assert_eq!(
        &buf[..n],
        hex("344233a6cabb7141d80f3da2fedc311d9646bbb0f505afe403a667")
    );
    let n = p.read_message(&buf[..n], &mut clear).unwrap();
    assert_eq!(&clear[..n], payload);
    let payload = hex("4a65616e2d426170746973746520536179");
    let n = p.write_message(&payload, &mut buf).unwrap();
    assert_eq!(
        &buf[..n],
        hex("62cdeeb172ad7ade7aa7d9e069da5790f12331bfa00177787a1d0810c67dc3b2b4")
    );
    let n = d.read_message(&buf[..n], &mut clear).unwrap();
    assert_eq!(&clear[..n], payload);
    let payload = hex("457567656e2042f6686d20766f6e2042617765726b");
    let n = d.write_message(&payload, &mut buf).unwrap();
    assert_eq!(
        &buf[..n],
        hex("029bead1b40992327044d409d9a1f3ad8f36c3c452775d557e18bbeb2e8dfcead32d514024")
    );
    let n = p.read_message(&buf[..n], &mut clear).unwrap();
    assert_eq!(&clear[..n], payload);
}

#[test]
fn cacophony_1() {
    let is = hex("e61ef9919cde45dd5f82166404bd08e38bceb5dfdfded0a34c8df7ed542214d1");
    let ie = hex("893e28b9dc6ca8d611ab664754b8ceb7bac5117349a4439a6b0569da977c464a");
    let rs = hex("31e0303fd6418d2f8c0e78b91f22e8caed0fbe48656dcf4767e4834f701b8f62");
    let ds = hex("4a3acbfdb163dec651dfa3194dece676d437029c62a408b4c5ea9114246e4893");
    let de = hex("bbdb4cdbd309f1a1f2e1456967fe288cadd6f712d65dc7b7793d5e63da6b375b");
    let pro = hex("4a6f686e2047616c74");
    let mut ib = snow::Builder::new("Noise_IKpsk2_25519_ChaChaPoly_SHA256".parse().unwrap())
        .local_private_key(&is)
        .unwrap()
        .remote_public_key(&rs)
        .unwrap()
        .prologue(&pro)
        .unwrap()
        .fixed_ephemeral_key_for_testing_only(&ie);
    let mut db = snow::Builder::new("Noise_IKpsk2_25519_ChaChaPoly_SHA256".parse().unwrap())
        .local_private_key(&ds)
        .unwrap()
        .prologue(&pro)
        .unwrap()
        .fixed_ephemeral_key_for_testing_only(&de);
    let psk = hex("54686973206973206d7920417573747269616e20706572737065637469766521");
    let psk: [u8; 32] = psk.try_into().unwrap();
    ib = ib.psk(2, &psk).unwrap();
    db = db.psk(2, &psk).unwrap();
    let mut p = ib.build_initiator().unwrap();
    let mut d = db.build_responder().unwrap();
    let mut buf = [0; 1024];
    let mut clear = [0; 1024];
    let payload = hex("4c756477696720766f6e204d69736573");
    let n = p.write_message(&payload, &mut buf).unwrap();
    assert_eq!(&buf[..n],hex("ca35def5ae56cec33dc2036731ab14896bc4c75dbb07a61f879f8e3afa4c79442ec9b09893d0f510791784c10cbc959f25b1766e0def6e301d14fbca1c7790ac829b8b3674f5f649a5f0e98479662cbfbf2b2c47cd4b09fcd266cd29d7cb675f1808849707847840f6d178ec4d3733aa"));
    let n = d.read_message(&buf[..n], &mut clear).unwrap();
    assert_eq!(&clear[..n], payload);
    let payload = hex("4d757272617920526f746862617264");
    let n = d.write_message(&payload, &mut buf).unwrap();
    assert_eq!(&buf[..n],hex("95ebc60d2b1fa672c1f46a8aa265ef51bfe38e7ccb39ec5be34069f1448088439a1b3cebf680b2c74217fcb5eba4ff58a9468cd90c4aca6194f57479b379a7"));
    let n = p.read_message(&buf[..n], &mut clear).unwrap();
    assert_eq!(&clear[..n], payload);
    assert_eq!(
        p.get_handshake_hash(),
        hex("8310f86394dc0dabb40beb8210031556db4403ab1202db7034c526232147a700")
    );
    assert_eq!(d.get_handshake_hash(), p.get_handshake_hash());
    let mut p = p.into_transport_mode().unwrap();
    let mut d = d.into_transport_mode().unwrap();
    let payload = hex("462e20412e20486179656b");
    let n = p.write_message(&payload, &mut buf).unwrap();
    assert_eq!(
        &buf[..n],
        hex("a8fde7a0accec190cd306c5950d4fd8e04a205ec288aa747d8b347")
    );
    let n = d.read_message(&buf[..n], &mut clear).unwrap();
    assert_eq!(&clear[..n], payload);
    let payload = hex("4361726c204d656e676572");
    let n = d.write_message(&payload, &mut buf).unwrap();
    assert_eq!(
        &buf[..n],
        hex("59caddd9984a3bbe24c4fb31a2bd455b7eba3fa0980674b1a3a5f9")
    );
    let n = p.read_message(&buf[..n], &mut clear).unwrap();
    assert_eq!(&clear[..n], payload);
    let payload = hex("4a65616e2d426170746973746520536179");
    let n = p.write_message(&payload, &mut buf).unwrap();
    assert_eq!(
        &buf[..n],
        hex("3b9bfebd210c22ba0cff9de79b4007d7a552fffbf92616881faa8a883e25b80258")
    );
    let n = d.read_message(&buf[..n], &mut clear).unwrap();
    assert_eq!(&clear[..n], payload);
    let payload = hex("457567656e2042f6686d20766f6e2042617765726b");
    let n = d.write_message(&payload, &mut buf).unwrap();
    assert_eq!(
        &buf[..n],
        hex("f37512df1043d564d7c46ac85c53d3b6a9a05724bc297e7142808f217561651217fe85b782")
    );
    let n = p.read_message(&buf[..n], &mut clear).unwrap();
    assert_eq!(&clear[..n], payload);
}
