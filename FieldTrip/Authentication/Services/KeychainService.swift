import Foundation
import Security
import LocalAuthentication

enum KeychainService {
    private static let service = "com.fieldtrip.app"

    enum Key: String {
        case authToken = "auth_token"
        case refreshToken = "refresh_token"
        case userId = "user_id"
        case biometricEmail = "biometric_email"
        case biometricPassword = "biometric_password"
    }

    // MARK: - Store

    @discardableResult
    static func store(_ value: String, for key: Key) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        // Try to update existing
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            // Item doesn't exist — add it
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }

        return status == errSecSuccess
    }

    // MARK: - Biometric-protected store

    /// Stores a value that can only be read after a successful biometric
    /// authentication, enforced by the Secure Enclave — not just by app logic.
    /// Bound to the currently-enrolled biometric set (`.biometryCurrentSet`),
    /// so the item is automatically invalidated if Face ID / Touch ID
    /// enrollment changes. Used for saved biometric-login credentials.
    @discardableResult
    static func storeBiometricProtected(_ value: String, for key: Key) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            nil
        ) else { return false }

        // Delete any existing item first so the access-control policy always
        // applies cleanly (SecItemUpdate can't reliably change it).
        delete(for: key)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: access,
        ]
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    // MARK: - Retrieve

    /// Retrieves a value. For biometric-protected items, pass the `LAContext`
    /// that has already evaluated a biometric policy so the Keychain read
    /// reuses that authentication instead of prompting a second time.
    static func retrieve(for key: Key, context: LAContext? = nil) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let context {
            query[kSecUseAuthenticationContext as String] = context
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }

        return string
    }

    // MARK: - Delete

    @discardableResult
    static func delete(for key: Key) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Clears the current sign-in session. Preserves biometric-login
    /// credentials so the user can use Face ID / Touch ID on the next sign-in
    /// without re-enabling.
    static func clearAll() {
        let sessionKeys: [Key] = [.authToken, .refreshToken, .userId]
        sessionKeys.forEach { delete(for: $0) }
    }

    /// Removes every keychain item this app owns, including the saved
    /// biometric credentials. Use on account deletion so no trace of the
    /// user remains on device.
    static func wipeEverything() {
        Key.allCases.forEach { delete(for: $0) }
    }
}

extension KeychainService.Key: CaseIterable {}
