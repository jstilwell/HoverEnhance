import Foundation
import Security

/// Strings kept in the login keychain, under this app's service name.
enum Keychain {
    private static let service = (Bundle.main.bundleIdentifier ?? "HoverEnhance") + ".accounts"

    struct Failure: LocalizedError, Equatable {
        let status: OSStatus

        var errorDescription: String? {
            let reason = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
            return "The Keychain couldn't save the sign-in: \(reason)"
        }
    }

    static func string(for account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Stores `value`, or removes the item when it's nil or empty. An existing item is updated in
    /// place, so a failed write never leaves it deleted.
    static func set(_ value: String?, for account: String) throws {
        let match: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
        guard let value, !value.isEmpty else {
            let status = SecItemDelete(match as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
            return
        }
        let data = Data(value.utf8)
        var status = SecItemUpdate(match as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = match
            item[kSecValueData] = data
            item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Failure(status: status) }
    }
}
