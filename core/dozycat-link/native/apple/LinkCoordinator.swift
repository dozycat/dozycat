import Foundation
import Network
import Security

/// One peer per installation in the first product integration. All callbacks are main-actor
/// serialized; each callback carries a generation so cancelled sockets cannot mutate a new link.
@MainActor
final class LinkCoordinator {
    struct Snapshot {
        var phase = "idle"
        var fingerprint = ""
        var invitation = ""
        var message = ""
        var paired = false
        var approved = false
    }
    var changed: ((Snapshot) -> Void)?
    var received: ((Data) throws -> Void)?
    private(set) var state = Snapshot()
    private let vault: LinkVault
    private var identity: LinkIdentity?
    private var invitation: LinkInvitation?
    private var handshake: LinkHandshake?
    private var session: LinkSession?
    private var peer: LinkPeer?
    private var reconnecting = false
    private var committed = false
    private var pendingWritten = false
    private var initiator = false
    private var remoteApproved = false
    private var localPersisted = false
    private var remotePersisted = false
    private var generation = UUID()
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var timeout: Task<Void, Never>?
    private let service = "_dozycat._tcp"

    init(vault: LinkVault) { self.vault = vault }
    func refresh() throws {
        state.paired = try vault.primaryPeer() != nil
        changed?(state)
    }
    private func publish(_ phase: String, _ message: String = "") {
        state.phase = phase; state.message = message; changed?(state)
    }
    private func begin(initiator: Bool, reconnect: Bool) throws {
        cancel()
        identity = try vault.identity()
        self.initiator = initiator
        reconnecting = reconnect
        peer = reconnect ? try vault.primaryPeer() : nil
        guard reconnect ? peer != nil : try vault.primaryPeer() == nil else { throw VaultError.unauthorized }
        state = Snapshot(paired: reconnect)
        let token = generation
        timeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 120_000_000_000) } catch { return }
            guard let self, self.generation == token else { return }
            self.fail("连接超时，请确认两台设备在同一 Wi-Fi 后重试。")
        }
    }
    var localPort: UInt16? { listener?.port?.rawValue }
    // advertise=false and endpoint override support isolated loopback integration tests.
    func host(advertise: Bool = true) throws {
        let reconnect = try vault.primaryPeer() != nil
        try begin(initiator: false, reconnect: reconnect)
        let room: Data
        if let peer { room = try peer.discoveryRoom(unixSeconds: UInt64(Date().timeIntervalSince1970)) }
        else {
            invitation = try identity!.invitation()
            room = try invitation!.room()
        }
        let token = generation
        let server = try NWListener(using: .tcp)
        if advertise { server.service = NWListener.Service(name: room.base64URL, type: service) }
        listener = server
        server.newConnectionHandler = { [weak self] candidate in
            Task { @MainActor in
                guard let self, self.generation == token, self.connection == nil else { candidate.cancel(); return }
                do {
                    if let peer = self.peer {
                        self.handshake = try self.identity!.reconnect(peer: peer, initiator: false, room: room)
                    } else { self.handshake = try self.invitation!.accept(identity: self.identity!) }
                    self.state.invitation = "" // one candidate, invitation cannot be raced or reused
                    self.listener?.cancel(); self.listener = nil
                    self.attach(candidate, token: token)
                } catch { candidate.cancel(); self.fail("无法建立安全握手，请重新生成连接码。") }
            }
        }
        server.stateUpdateHandler = { [weak self] update in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                switch update {
                case .ready:
                    do {
                        if let invite = self.invitation {
                            let object: [String: Any] = ["version": 1, "room_id": try invite.room().base64URL,
                                "desktop_public_key": self.identity!.publicKey().base64URL,
                                "psk": try invite.secretForQr().base64URL,
                                "expires_at": Int(Date().timeIntervalSince1970 * 1000) + 120_000]
                            var url = URLComponents(); url.scheme = "dozycat"; url.host = "pair"
                            url.queryItems = [URLQueryItem(name: "data", value: String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8)!)]
                            self.state.invitation = url.string!
                        }
                        self.publish("waiting", reconnect ? "等待已绑定的手机连接" : "请用手机扫描连接码")
                    } catch { self.fail("无法生成连接码。") }
                case .failed: self.fail("无法开启本地连接，请检查局域网权限。")
                default: break
                }
            }
        }
        publish("starting")
        server.start(queue: .main)
    }
    func pair(_ uri: String, endpoint: NWEndpoint? = nil) throws {
        let invite = try LinkQR(uri)
        try begin(initiator: true, reconnect: false)
        handshake = try identity!.pair(desktop: invite.publicKey, room: invite.room, secret: invite.secret)
        if let endpoint { attach(NWConnection(to: endpoint, using: .tcp), token: generation) }
        else { discover(rooms: [invite.room]) }
    }
    func reconnect(endpoint: NWEndpoint? = nil) throws {
        try begin(initiator: true, reconnect: true)
        let now = UInt64(Date().timeIntervalSince1970)
        let rooms = try [now, now >= 300 ? now - 300 : 0, now + 300].map { try peer!.discoveryRoom(unixSeconds: $0) }
        if let endpoint {
            handshake = try identity!.reconnect(peer: peer!, initiator: true, room: rooms[0])
            attach(NWConnection(to: endpoint, using: .tcp), token: generation)
        } else { discover(rooms: rooms) }
    }
    private func discover(rooms: [Data]) {
        let token = generation
        let scan = NWBrowser(for: .bonjour(type: service, domain: nil), using: .tcp)
        browser = scan
        scan.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self, self.generation == token, self.connection == nil else { return }
                for result in results {
                    guard case let .service(name, _, _, _) = result.endpoint,
                          let room = rooms.first(where: { $0.base64URL == name }) else { continue }
                    do {
                        if let peer = self.peer {
                            self.handshake = try self.identity!.reconnect(peer: peer, initiator: true, room: room)
                        }
                        self.browser?.cancel(); self.browser = nil
                        self.attach(NWConnection(to: result.endpoint, using: .tcp), token: token)
                    } catch { self.fail("无法验证已绑定的电脑。") }
                    return
                }
            }
        }
        scan.stateUpdateHandler = { [weak self] update in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                if case .failed = update { self.fail("找不到电脑，请允许局域网访问并确认在同一 Wi-Fi。") }
            }
        }
        publish("discovering", "正在同一 Wi-Fi 中寻找电脑")
        scan.start(queue: .main)
    }
    private func attach(_ socket: NWConnection, token: UUID) {
        connection = socket
        publish("handshaking", "正在验证设备身份")
        socket.stateUpdateHandler = { [weak self] update in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                switch update {
                case .ready:
                    do {
                        if self.initiator { self.send(try self.handshake!.write()) }
                        self.readHeader(socket, token: token)
                    } catch { self.fail("安全握手失败。") }
                case .failed: self.fail("连接已中断，请重试。")
                case .waiting: self.publish("connecting", "正在等待本地网络")
                default: break
                }
            }
        }
        socket.start(queue: .main)
    }
    private func readHeader(_ socket: NWConnection, token: UUID) {
        socket.receive(minimumIncompleteLength: 2, maximumLength: 2) { [weak self] data, _, ended, error in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                guard error == nil, !ended, let data, data.count == 2 else { self.fail("连接已断开。"); return }
                let length = Int(data[0]) * 256 + Int(data[1])
                guard length > 0, length <= 60_016 else { self.fail("收到无效连接数据。"); return }
                socket.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, _, error in
                    Task { @MainActor in
                        guard let self, self.generation == token else { return }
                        guard error == nil, let data, data.count == length else { self.fail("连接数据不完整。"); return }
                        do {
                            try self.handle(data)
                            if self.generation == token { self.readHeader(socket, token: token) }
                        } catch { self.fail("设备验证或保存失败，未开放同步。") }
                    }
                }
            }
        }
    }
    private func send(_ frame: Data) {
        guard let connection, !frame.isEmpty, frame.count <= 60_016 else { fail("连接不可用。"); return }
        let token = generation
        let prefix = Data([UInt8(frame.count >> 8), UInt8(frame.count & 255)])
        connection.send(content: prefix + frame, completion: .contentProcessed { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.fail("发送中断，请重新连接。")
            }
        })
    }
    private func handle(_ frame: Data) throws {
        if let handshake {
            try handshake.read(frame: frame)
            if !initiator { send(try handshake.write()) }
            session = try handshake.finish(); self.handshake = nil
            if reconnecting {
                guard let key = try peer?.publicKey(), let current = try vault.activePeer(key) else { throw VaultError.unauthorized }
                try session!.authorizeReconnect(peer: current)
                committed = true; timeout?.cancel(); publish("connected", "已建立加密连接")
            } else {
                state.fingerprint = try session!.fingerprint()
                publish("compare", "请核对两端校验码，并分别确认连接")
            }
            return
        }
        guard let session else { throw VaultError.unauthorized }
        switch try session.receive(ciphertext: frame) {
        case .approved:
            remoteApproved = true
            try offerIfReady()
        case .bindingOffered:
            guard initiator else { throw VaultError.unauthorized }
            try persistAndAcknowledge()
        case .persisted:
            remotePersisted = true
            try activateIfReady()
        case .data(let bytes):
            guard state.phase == "connected", let key = try peer?.publicKey(), try vault.activePeer(key) != nil else { throw VaultError.unauthorized }
            try received?(bytes)
        }
    }
    func approve(expectedFingerprint: String) throws {
        guard state.phase == "compare", !state.approved, !expectedFingerprint.isEmpty, expectedFingerprint == state.fingerprint, let session else { throw VaultError.unauthorized }
        state.approved = true
        send(try session.approve())
        try offerIfReady()
        changed?(state)
    }
    private func offerIfReady() throws {
        guard !initiator, state.approved, remoteApproved, peer == nil, let session else { return }
        let workspace = try vault.workspace()
        send(try session.offerBinding(workspace: workspace))
        try persistAndAcknowledge()
    }
    private func persistAndAcknowledge() throws {
        guard !localPersisted, let session else { throw VaultError.unauthorized }
        peer = try session.pendingPeer()
        try vault.savePending(peer!)
        pendingWritten = true
        // Publish the pointer while the record is still PENDING. A failed index write
        // cannot leave an ACTIVE grant that the device list cannot find.
        try vault.setPrimary(peer!)
        let ack = try session.acknowledgePersisted()
        localPersisted = true
        send(ack)
        try activateIfReady()
    }
    private func activateIfReady() throws {
        guard localPersisted, remotePersisted, !committed, let peer, let session else { return }
        try vault.activate(peer)
        do {
            try session.activateAfterAclCommit()
        } catch {
            try? vault.remove(peer.publicKey()); throw error
        }
        committed = true; state.paired = true; timeout?.cancel()
        publish("connected", "已建立加密连接")
    }
    func sendPayload(_ bytes: Data) throws {
        guard state.phase == "connected", let peer, let session,
              try vault.activePeer(peer.publicKey()) != nil else { throw VaultError.unauthorized }
        // Workspace is selected by the approved peer record, never by untrusted UI input.
        let record = try peer.bytesForNativeStorage()
        send(try session.sendData(workspace: Data(record[81..<97]), payload: bytes))
    }
    func removeDevice() throws {
        let key = try vault.primaryPeer()?.publicKey()
        cancel() // stop all current work even if secure storage subsequently fails
        if let key { try vault.remove(key) }
        try vault.clearPrimary()
        state = Snapshot(); changed?(state)
    }
    func cancel() {
        generation = UUID(); timeout?.cancel(); timeout = nil
        browser?.cancel(); browser = nil; listener?.cancel(); listener = nil
        connection?.cancel(); connection = nil
        try? invitation?.cancel(); invitation = nil; handshake = nil
        try? session?.close(); session = nil
        if pendingWritten && !committed, let peer { try? vault.remove(peer.publicKey()) }
        peer = nil; committed = false; pendingWritten = false; remoteApproved = false; localPersisted = false; remotePersisted = false
        state.fingerprint = ""; state.invitation = ""; state.approved = false
        state.paired = (try? vault.primaryPeer()) != nil
        publish("idle")
    }
    private func fail(_ message: String) { cancel(); publish("error", message) }
}

struct LinkQR {
    let room: Data, publicKey: Data, secret: Data
    init(_ text: String, now: Date = Date()) throws {
        guard text.utf8.count <= 2048, let url = URLComponents(string: text),
              url.scheme == "dozycat", url.host == "pair", url.path.isEmpty,
              url.user == nil, url.password == nil, url.port == nil, url.fragment == nil,
              let items = url.queryItems, items.count == 1, items[0].name == "data",
              let data = items[0].value?.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String:Any],
              let version = object["version"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 1,
              let expires = object["expires_at"] as? Double, expires.isFinite, expires.rounded(.towardZero) == expires,
              expires > now.timeIntervalSince1970 * 1000,
              expires <= now.timeIntervalSince1970 * 1000 + 120_000,
              let room = Data(base64URL: object["room_id"] as? String, count: 16),
              let key = Data(base64URL: object["desktop_public_key"] as? String, count: 32),
              let secret = Data(base64URL: object["psk"] as? String, count: 32) else { throw VaultError.corrupt }
        self.room = room; publicKey = key; self.secret = secret
    }
}
extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    init?(base64URL string: String?, count: Int) {
        guard let string, string.utf8.count == (count * 8 + 5) / 6,
              string.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }),
              let bytes = Data(base64Encoded: string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + String(repeating: "=", count: (4 - string.count % 4) % 4)),
              bytes.count == count, bytes.base64URL == string else { return nil }
        self = bytes
    }
}
