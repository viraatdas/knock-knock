import Foundation
import Security

/// Thin Keychain wrapper for secure token storage.
struct Keychain {
    let service: String

    init(service: String = "app.slide.tokens") {
        self.service = service
    }

    func set(_ value: String, for key: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    func remove(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Stores access + refresh tokens in the Keychain.
final class TokenStore: @unchecked Sendable {
    static let shared = TokenStore()

    private let keychain = Keychain()
    private let accessKey = "accessToken"
    private let refreshKey = "refreshToken"
    private let pushTokenKey = "devicePushToken"
    private let lock = NSLock()

    var accessToken: String? {
        lock.lock(); defer { lock.unlock() }
        return keychain.get(accessKey)
    }

    var refreshToken: String? {
        lock.lock(); defer { lock.unlock() }
        return keychain.get(refreshKey)
    }

    var isAuthenticated: Bool { accessToken != nil }

    /// The most recent APNs device token (see `AppDelegate.
    /// didRegisterForRemoteNotificationsWithDeviceToken`), kept independent
    /// of `clear()` so a sign-out can still unregister it, and a later
    /// sign-in on the same device can re-claim it without waiting for a
    /// fresh callback from the OS.
    var devicePushToken: String? {
        get { lock.lock(); defer { lock.unlock() }; return keychain.get(pushTokenKey) }
        set {
            lock.lock(); defer { lock.unlock() }
            if let newValue { keychain.set(newValue, for: pushTokenKey) }
            else { keychain.remove(pushTokenKey) }
        }
    }

    func save(access: String, refresh: String) {
        lock.lock(); defer { lock.unlock() }
        keychain.set(access, for: accessKey)
        keychain.set(refresh, for: refreshKey)
    }

    func updateAccess(_ access: String, refresh: String) {
        lock.lock(); defer { lock.unlock() }
        keychain.set(access, for: accessKey)
        keychain.set(refresh, for: refreshKey)
    }

    /// Clears only the session tokens. `devicePushToken` deliberately
    /// survives a sign-out/sign-in so the next account on this device can
    /// still be told which token it owns.
    func clear() {
        lock.lock(); defer { lock.unlock() }
        keychain.remove(accessKey)
        keychain.remove(refreshKey)
    }
}
