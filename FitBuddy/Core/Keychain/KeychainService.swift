import Foundation
import OSLog
import Security

/// Thread-safe wrapper around the iOS Keychain for FitBuddy's secrets and
/// consent metadata.
///
/// All items are stored as `kSecClassGenericPassword` under a single service,
/// keyed by `KeychainKey`. Every item is protected with
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, so secrets never leave the
/// device and are unavailable while the device is locked.
///
/// - Note: No `kSecAttrAccessGroup` is set. FitBuddy v0 is a single app target
///   with no extensions or sibling apps, so the default access group is used.
///   This is a deliberate deviation from the literal issue wording; an explicit
///   access group would require a Keychain Sharing entitlement we do not need.
actor KeychainService {
    /// Shared `kSecAttrService` value for all FitBuddy items.
    private static let service = "ch.bfh.fitbuddy"

    private let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "KeychainService")

    init() {}

    // MARK: - Public API

    /// Stores `value` for `key`, inserting or updating as needed.
    ///
    /// Attempts `SecItemAdd` first and falls back to `SecItemUpdate` only on
    /// `errSecDuplicateItem`. This is a single atomic Keychain call in the
    /// common (insert) case and has no check-then-act race: a concurrent writer
    /// that wins the add simply routes us to the update branch.
    func save(_ value: String, for key: KeychainKey) throws {
        let data = Data(value.utf8)

        var addQuery = baseQuery(for: key)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecDuplicateItem else {
            try check(addStatus, operation: "SecItemAdd")
            return
        }

        // Item already exists → update its value in place.
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery(for: key) as CFDictionary, attributes as CFDictionary)
        try check(updateStatus, operation: "SecItemUpdate")
    }

    /// Returns the stored string for `key`, or `nil` if no item exists.
    func read(_ key: KeychainKey) throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidData
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            try check(status, operation: "SecItemCopyMatching")
            return nil
        }
    }

    /// Deletes the item for `key`. A missing item is treated as success.
    func delete(_ key: KeychainKey) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        try check(status, operation: "SecItemDelete", tolerating: errSecItemNotFound)
    }

    /// Returns whether an item exists for `key`.
    ///
    /// Useful after a reinstall, since generic-password items can outlive app
    /// deletion on iOS.
    func exists(_ key: KeychainKey) throws -> Bool {
        let status = SecItemCopyMatching(baseQuery(for: key) as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            return false
        default:
            try check(status, operation: "SecItemCopyMatching")
            return false
        }
    }

    // MARK: - Helpers

    /// Maps an `OSStatus` to a thrown `KeychainError`, logging the failing
    /// operation. Returns normally for `errSecSuccess` and any explicitly
    /// tolerated status (e.g. `errSecItemNotFound` on delete).
    private func check(
        _ status: OSStatus,
        operation: String,
        tolerating tolerated: OSStatus...
    ) throws {
        guard status != errSecSuccess, !tolerated.contains(status) else { return }
        logger.error("\(operation, privacy: .public) failed: \(status, privacy: .public)")
        throw KeychainError.unexpectedStatus(status)
    }

    /// Base query identifying a single item by class, service and account.
    private func baseQuery(for key: KeychainKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: key.rawValue,
        ]
    }
}
