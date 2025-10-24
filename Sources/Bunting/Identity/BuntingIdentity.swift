import Foundation
import Security

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

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        // If item doesn't exist, add it
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrSynchronizable as String] = true  // Enable iCloud Keychain sync
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

            status = SecItemAdd(addQuery as CFDictionary, nil)
        }

        guard status == errSecSuccess else {
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
