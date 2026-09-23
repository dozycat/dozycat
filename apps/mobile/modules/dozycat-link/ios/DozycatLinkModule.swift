import ExpoModulesCore
import Foundation

public final class DozycatLinkModule: Module {
    @MainActor private var link: LinkCoordinator?
    @MainActor private func controller() -> LinkCoordinator {
        if let link { return link }
        let service = (Bundle.main.bundleIdentifier ?? "com.paperboytm.dozycat") + ".device-link.v1"
        let link = LinkCoordinator(vault: LinkVault(storage: KeychainLinkStorage(service: service)))
        link.changed = { [weak self] state in self?.sendEvent("onStatus", Self.snapshot(state)) }
        self.link = link
        return link
    }
    private static func snapshot(_ state: LinkCoordinator.Snapshot) -> [String: Any] {
        ["phase": state.phase, "fingerprint": state.fingerprint, "message": state.message,
         "paired": state.paired, "approved": state.approved]
    }
    public func definition() -> ModuleDefinition {
        Name("DozycatLink")
        Events("onStatus")
        AsyncFunction("status") { () async throws -> [String: Any] in
            try await MainActor.run {
                let link = self.controller(); try link.refresh(); return Self.snapshot(link.state)
            }
        }
        AsyncFunction("pair") { (invite: String) async throws in
            try await MainActor.run { try self.controller().pair(invite) }
        }
        AsyncFunction("approve") { (fingerprint: String) async throws in
            try await MainActor.run { try self.controller().approve(expectedFingerprint: fingerprint) }
        }
        AsyncFunction("reconnect") { () async throws in
            try await MainActor.run { try self.controller().reconnect() }
        }
        AsyncFunction("cancel") { () async in
            await MainActor.run { self.controller().cancel() }
        }
        AsyncFunction("removeDevice") { () async throws in
            try await MainActor.run { try self.controller().removeDevice() }
        }
        OnDestroy {
            Task { @MainActor in self.link?.cancel(); self.link = nil }
        }
    }
}
