import Foundation
import Network

final class IsolatedStorage: LinkSecureStorage {
    var values: [String: Data] = [:]
    var rejectWrites = false
    func read(_ account: String) throws -> Data? { values[account] }
    func write(_ account: String, data: Data) throws {
        if rejectWrites { throw VaultError.unauthorized }; values[account] = data
    }
    func remove(_ account: String) throws { values.removeValue(forKey: account) }
}
@main
struct CoordinatorSmoke {
    @MainActor static func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<500 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw NSError(domain: "CoordinatorSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: "State transition timed out"])
    }
    static func check(_ condition: Bool) { precondition(condition) }
    @MainActor static func main() async throws {
        let pv = LinkVault(storage: IsolatedStorage()), dv = LinkVault(storage: IsolatedStorage())
        let desktop = LinkCoordinator(vault: dv), phone = LinkCoordinator(vault: pv)
        defer { desktop.cancel(); phone.cancel() }
        try desktop.host(advertise: false)
        try await wait { desktop.state.phase == "waiting" }
        let uri = desktop.state.invitation
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: desktop.localPort!)!)
        try phone.pair(uri, endpoint: endpoint)
        try await wait { desktop.state.phase == "compare" && phone.state.phase == "compare" }
        precondition(!phone.state.fingerprint.isEmpty && desktop.state.fingerprint == phone.state.fingerprint)
        do { try phone.approve(expectedFingerprint: "stale fingerprint"); preconditionFailure("stale confirmation accepted") } catch {}
        try phone.approve(expectedFingerprint: phone.state.fingerprint)
        try await Task.sleep(nanoseconds: 50_000_000)
        precondition(!phone.state.paired && !desktop.state.paired)
        try desktop.approve(expectedFingerprint: desktop.state.fingerprint)
        try await wait { desktop.state.phase == "connected" && phone.state.phase == "connected" }
        var payload: Data?
        desktop.received = { payload = $0 }
        try phone.sendPayload(Data("真实原生连接测试".utf8))
        try await wait { payload != nil }
        precondition(payload == Data("真实原生连接测试".utf8))
        phone.cancel()
        try await wait { desktop.state.phase == "error" }
        try check(pv.primaryPeer() != nil)
        try check(dv.primaryPeer() != nil)
        // Cancellation of a reconnect must NEVER delete the existing active ACL.
        try phone.reconnect(endpoint: .hostPort(host: "127.0.0.1", port: 1))
        phone.cancel()
        try check(pv.primaryPeer() != nil)
        try desktop.host(advertise: false)
        try await wait { desktop.state.phase == "waiting" }
        try phone.reconnect(endpoint: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: desktop.localPort!)!))
        try await wait { desktop.state.phase == "connected" && phone.state.phase == "connected" }
        try phone.removeDevice()
        try check(pv.primaryPeer() == nil)
        do { try phone.sendPayload(Data([1])); preconditionFailure("revoked device sent data") } catch {}
        try await wait { desktop.state.phase == "error" }
        try check(dv.primaryPeer() != nil) // unilateral revocation does not fabricate a remote wipe
        let failingStorage = IsolatedStorage()
        let failedPhoneVault = LinkVault(storage: failingStorage)
        let failedDesktopVault = LinkVault(storage: IsolatedStorage())
        let failedPhone = LinkCoordinator(vault: failedPhoneVault)
        let failedDesktop = LinkCoordinator(vault: failedDesktopVault)
        defer { failedPhone.cancel(); failedDesktop.cancel() }
        try failedDesktop.host(advertise: false)
        try await wait { failedDesktop.state.phase == "waiting" }
        try failedPhone.pair(failedDesktop.state.invitation, endpoint: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: failedDesktop.localPort!)!))
        try await wait { failedPhone.state.phase == "compare" && failedDesktop.state.phase == "compare" }
        failingStorage.rejectWrites = true
        try failedPhone.approve(expectedFingerprint: failedPhone.state.fingerprint)
        try failedDesktop.approve(expectedFingerprint: failedDesktop.state.fingerprint)
        try await wait { failedPhone.state.phase == "error" && failedDesktop.state.phase == "error" }
        try check(failedPhoneVault.primaryPeer() == nil)
        try check(failedDesktopVault.primaryPeer() == nil)
        print("Native coordinator: TCP discovery bypass, QR parse, dual approval, encrypted payload, reconnect, cancellation and revocation passed")
    }
}
