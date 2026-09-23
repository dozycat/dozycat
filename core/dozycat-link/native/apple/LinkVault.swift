import Foundation
import Security

/// Only native code may access this vault. Never expose identity/peer blobs to React Native.
protocol LinkSecureStorage {
    func read(_ account: String) throws -> Data?
    func write(_ account: String, data: Data) throws
    func remove(_ account: String) throws
}

struct KeychainLinkStorage: LinkSecureStorage {
    let service: String
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }
    func read(_ account: String) throws -> Data? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw VaultError.keychain(status) }
        return data
    }
    func write(_ account: String, data: Data) throws {
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let q = query(account)
        var status = SecItemUpdate(q as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(q.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw VaultError.keychain(status) }
    }
    func remove(_ account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw VaultError.keychain(status) }
    }
}
enum VaultError: Error { case keychain(OSStatus), corrupt, unauthorized }

/// Prefix and peer blob are one atomic Keychain item. PENDING can never load as ACTIVE.
final class LinkVault {
    private let storage: any LinkSecureStorage
    init(storage: any LinkSecureStorage) { self.storage = storage }
    func identity() throws -> LinkIdentity {
        if let bytes = try storage.read("identity.v1") {
            guard bytes.count == 32 else { throw VaultError.corrupt }
            return try LinkIdentity.restore(privateKey: bytes)
        }
        let identity = try LinkIdentity.generate()
        try storage.write("identity.v1", data: identity.privateKeyForNativeStorage())
        return identity
    }
    private func account(_ publicKey: Data) -> String { "peer.v1." + publicKey.base64EncodedString() }
    func savePending(_ peer: LinkPeer) throws {
        let key = try peer.publicKey()
        // An active peer requires an explicit removal before pairing it again.
        if try activePeer(key) != nil { throw VaultError.unauthorized }
        try storage.write(account(key), data: Data([0]) + peer.bytesForNativeStorage())
    }
    func activate(_ peer: LinkPeer) throws {
        let key = try peer.publicKey()
        guard let old = try storage.read(account(key)), old.first == 0,
              old.dropFirst() == (try peer.bytesForNativeStorage()) else { throw VaultError.unauthorized }
        try storage.write(account(key), data: Data([1]) + peer.bytesForNativeStorage())
    }
    func activePeer(_ publicKey: Data) throws -> LinkPeer? {
        guard let bytes = try storage.read(account(publicKey)) else { return nil }
        guard bytes.count == 100, bytes.first == 0 || bytes.first == 1 else { throw VaultError.corrupt }
        guard bytes.first == 1 else { return nil }
        let peer = try LinkPeer.fromNativeStorage(bytes: Data(bytes.dropFirst()))
        guard try peer.publicKey() == publicKey else { throw VaultError.corrupt }
        return peer
    }
    func workspace() throws -> Data {
        if let bytes = try storage.read("workspace.v1") {
            guard bytes.count == 16 else { throw VaultError.corrupt }; return bytes
        }
        var bytes = Data(count: 16)
        let status = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard status == errSecSuccess else { throw VaultError.keychain(status) }
        try storage.write("workspace.v1", data: bytes); return bytes
    }
    func primaryPeer() throws -> LinkPeer? {
        guard let key = try storage.read("primary.v1") else { return nil }
        guard key.count == 32 else { throw VaultError.corrupt }
        return try activePeer(key)
    }
    func setPrimary(_ peer: LinkPeer) throws { try storage.write("primary.v1", data: peer.publicKey()) }
    func clearPrimary() throws { try storage.remove("primary.v1") }
    func remove(_ publicKey: Data) throws {
        try storage.remove(account(publicKey))
        if try storage.read("primary.v1") == publicKey { try storage.remove("primary.v1") }
    }
}
