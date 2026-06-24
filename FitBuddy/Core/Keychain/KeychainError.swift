import Foundation

/// Errors thrown by `KeychainService`.
enum KeychainError: Error, Equatable {
    /// A Security framework call returned a non-success `OSStatus`.
    case unexpectedStatus(OSStatus)
    /// Stored data could not be decoded into a UTF-8 string.
    case invalidData
}
