import Foundation
import Security
import OSLog

/// Manages the persistent local identity for deterministic bucketing
actor BuntingIdentity {
    private let keychainAccessGroup: String?
    private var cachedLocalID: UUID?

    private static let keychainServiceName = "com.bunting.identity"
    private static let keychainAccountName = "local_id"

    init(keychainAccessGroup: String? = nil) {
        self.keychainAccessGroup = keychainAccessGroup
    }

    /// Returns the persistent local ID, creating one if needed
    func getLocalID() throws -> UUID {
        if let cached = cachedLocalID {
            return cached
        }

        // Try to load from keychain
        if let existing = try? loadFromKeychain() {
            cachedLocalID = existing
            return existing
        }

        // Generate new UUID and save to keychain
        let newID = UUID()
        try saveToKeychain(newID)
        cachedLocalID = newID
        return newID
    }

    /// Resets the local identity (generates a new UUID)
    func resetIdentity() throws {
        let newID = UUID()
        try saveToKeychain(newID)
        cachedLocalID = newID
    }

    // MARK: - Keychain Operations

    private func loadFromKeychain() throws -> UUID? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainServiceName,
            kSecAttrAccount as String: Self.keychainAccountName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        if let accessGroup = keychainAccessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw BuntingError.keychainError(status: status)
        }

        guard let data = result as? Data,
            let uuidString = String(data: data, encoding: .utf8),
            let uuid = UUID(uuidString: uuidString)
        else {
            throw BuntingError.invalidKeychainData
        }

        return uuid
    }

    private func saveToKeychain(_ uuid: UUID) throws {
        let data = uuid.uuidString.data(using: .utf8)!

        // First try to update existing item
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainServiceName,
            kSecAttrAccount as String: Self.keychainAccountName,
        ]

        if let accessGroup = keychainAccessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        var attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        // If item doesn't exist, add it
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            #if os(iOS) || os(tvOS) || os(watchOS)
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            #endif

            status = SecItemAdd(addQuery as CFDictionary, nil)

            // If missing entitlement or unsupported attribute caused failure, log and retry with minimal attributes
            if status != errSecSuccess {
                BuntingLog.core.error("Keychain add failed (status: \(status), privacy: .public). Retrying with minimal attributes.")
                var minimal = query
                minimal[kSecValueData as String] = data
                status = SecItemAdd(minimal as CFDictionary, nil)
            }
        }

        guard status == errSecSuccess else {
            BuntingLog.core.error("Keychain write failed with status: \(status), privacy: .public")
            throw BuntingError.keychainError(status: status)
        }
    }
}

/// Errors that can occur in Bunting SDK
public enum BuntingError: Error, Sendable {
    case keychainError(status: OSStatus)
    case invalidKeychainData
    case configurationNotLoaded
    case signatureVerificationFailed
    case invalidConfiguration
    case networkError(Error)
    case flagNotFound(String)
    case typeMismatch(expected: FlagType, actual: FlagType)
}
