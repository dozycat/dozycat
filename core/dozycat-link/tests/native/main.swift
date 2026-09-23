import Foundation

// Native FFI + ACL smoke test. All keys and records are isolated in memory;
// this executable does not read/write the user's Keychain or application data.
final class MemoryStorage: LinkSecureStorage {
    var values: [String:Data] = [:]
    var rejectWrites = false
    func read(_ account: String) throws -> Data? { values[account] }
    func write(_ account: String, data: Data) throws {
        if rejectWrites { throw VaultError.unauthorized }
        values[account] = data
    }
    func remove(_ account: String) throws { values.removeValue(forKey: account) }
}
func require(_ condition: Bool) { precondition(condition) }
let pm = MemoryStorage(), dm = MemoryStorage()
let pv = LinkVault(storage: pm), dv = LinkVault(storage: dm)
let phone = try pv.identity(), desktop = try dv.identity()
require(try pv.identity().publicKey() == phone.publicKey())
let invite = try desktop.invitation()
let p = try phone.pair(desktop: desktop.publicKey(), room: invite.room(), secret: invite.secretForQr())
let d = try invite.accept(identity: desktop)
try d.read(frame: p.write())
try p.read(frame: d.write())
let ps = try p.finish(), ds = try d.finish()
require(try ps.fingerprint() == ds.fingerprint())
_ = try ds.receive(ciphertext: ps.approve())
_ = try ps.receive(ciphertext: ds.approve())
let workspace = Data(repeating: 7, count: 16)
_ = try ps.receive(ciphertext: ds.offerBinding(workspace: workspace))
let pp = try ps.pendingPeer(), dp = try ds.pendingPeer()
try pv.savePending(pp)
try dv.savePending(dp)
require(try pv.activePeer(desktop.publicKey()) == nil)
require(try dv.activePeer(phone.publicKey()) == nil)
_ = try ds.receive(ciphertext: ps.acknowledgePersisted())
_ = try ps.receive(ciphertext: ds.acknowledgePersisted())
try pv.activate(pp)
try dv.activate(dp)
try ps.activateAfterAclCommit()
try ds.activateAfterAclCommit()
let ciphertext = try ps.sendData(workspace: workspace, payload: Data("native smoke".utf8))
switch try ds.receive(ciphertext: ciphertext) {
case .data(let bytes): require(bytes == Data("native smoke".utf8))
default: preconditionFailure()
}
require(try pv.activePeer(desktop.publicKey()) != nil)
try pv.remove(desktop.publicKey())
try ps.close()
require(try pv.activePeer(desktop.publicKey()) == nil)
do { _ = try ps.sendData(workspace: workspace, payload: Data([1])); preconditionFailure() } catch {}
let broken = MemoryStorage(); broken.rejectWrites = true
// A failed Keychain write cannot yield an apparently persisted identity.
do { _ = try LinkVault(storage: broken).identity(); preconditionFailure() } catch {}
print("Native Swift/Rust pairing, protected-store boundary, pending ACL and revocation checks passed")

let now = Date(timeIntervalSince1970: 1000)
let valid: [String: Any] = ["version": 1, "expires_at": 1_060_000,
    "room_id": Data(repeating: 0, count: 16).base64URL,
    "desktop_public_key": Data(repeating: 1, count: 32).base64URL,
    "psk": Data(repeating: 2, count: 32).base64URL]
func qr(_ object: [String: Any], host: String = "pair") throws -> String {
    var url = URLComponents(); url.scheme = "dozycat"; url.host = host
    url.queryItems = [URLQueryItem(name: "data", value: String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8))]
    return url.string!
}
_ = try LinkQR(qr(valid), now: now)
for (field, value) in [("version", true as Any), ("expires_at", 1_000_000 as Any),
                       ("expires_at", 1_060_000.5 as Any), ("room_id", "AAAAAAAAAAAAAAAAAAAAAB" as Any)] {
    var invalid = valid; invalid[field] = value
    do { _ = try LinkQR(qr(invalid), now: now); preconditionFailure("invalid QR accepted") } catch {}
}
for suffix in ["&extra=value", "#fragment"] {
    do { _ = try LinkQR(qr(valid) + suffix, now: now); preconditionFailure("invalid URL accepted") } catch {}
}
print("Native QR canonical encoding, expiry, type and URL checks passed")
