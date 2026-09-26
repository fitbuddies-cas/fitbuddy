import Foundation
import OSLog

/// How an `AnalysisValidationLog` is stored in
/// `AnalysisResult.validationLogJSON` and read back (#228).
///
/// The same shape as `SessionCountFormat`: one JSON blob next to the row, read
/// through this type and never through `JSONDecoder` directly. A log is a
/// diagnostic, not what the screen renders, so every failure reads as "not
/// recorded" and leaves the analysis itself untouched.
enum AnalysisValidationLogFormat {
    private static let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "AnalysisValidationLogFormat")

    /// The bytes to store for `log` — `nil` when there is none (a prose
    /// answer) or it cannot be encoded.
    static func encode(_ log: AnalysisValidationLog?) -> Data? {
        guard let log else { return nil }
        do {
            return try JSONEncoder().encode(log)
        } catch {
            logger.error("Validation log not encoded: \(error, privacy: .public)")
            return nil
        }
    }

    /// The log stored as `json`, or `nil` for a row without one — every row
    /// before V7 — and for a log this build cannot read, e.g. one naming a
    /// reason a newer build added.
    static func decode(_ json: Data?) -> AnalysisValidationLog? {
        guard let json else { return nil }
        do {
            return try JSONDecoder().decode(AnalysisValidationLog.self, from: json)
        } catch {
            logger.error("Validation log not decoded: \(error, privacy: .public)")
            return nil
        }
    }
}
