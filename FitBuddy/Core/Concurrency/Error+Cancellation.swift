import Foundation

extension Error {
    /// Whether this error means "the caller cancelled", not "something went
    /// wrong".
    ///
    /// `URLSession` reports a cancelled request as `URLError.cancelled` rather
    /// than `CancellationError`, so both forms have to be recognised — and a
    /// cancellation must never reach the user as an offline banner or an
    /// analysis error.
    var isCancellation: Bool {
        self is CancellationError || (self as? URLError)?.code == .cancelled
    }
}
