import Foundation
import Security

/// Persists the backend session JWT in the iOS Keychain so it survives
/// app restarts. Wrapped in an actor so the APIClient can await reads.
actor AuthStore {
    static let shared = AuthStore()

    private let service = "com.example.BeerTracker"
    private let account = "session-token"

    private(set) var token: String?

    private init() {
        self.token = readKeychain()
    }

    func setToken(_ token: String?) {
        self.token = token
        if let token = token {
            writeKeychain(token)
        } else {
            deleteKeychain()
        }
    }

    // MARK: - Keychain helpers

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func readKeychain() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let s = String(data: data, encoding: .utf8) else {
            return nil
        }
        return s
    }

    private func writeKeychain(_ value: String) {
        let data = Data(value.utf8)
        var query = baseQuery()
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    private func deleteKeychain() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}
