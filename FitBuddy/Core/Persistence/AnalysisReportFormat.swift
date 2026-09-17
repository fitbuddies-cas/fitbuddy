import Foundation
import OSLog

/// How a `ValidatedAnalysisReport` is stored in `AnalysisResult.reportJSON`,
/// and which formats this build can read back (US-14 AC6, #176).
///
/// The version travels with the bytes so a later change to the report's shape
/// can be told apart from today's instead of failing to decode silently. A row
/// whose version this build does not know, or whose JSON does not decode,
/// reads as prose: `text` is always stored alongside, and a history entry
/// without cards is better than a history that crashes or loses the row.
enum AnalysisReportFormat {
    /// No report — the row holds prose only. The V3 → V4 default.
    static let prose = 0
    /// `ValidatedAnalysisReport` as `JSONEncoder` writes it (#175, #176).
    static let validatedReportV1 = 1

    private static let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "AnalysisReportFormat")

    /// The bytes and version to store for `report`: `(nil, prose)` when there
    /// is no report, or when it cannot be encoded — the row then keeps its
    /// text and nothing claims a format it does not hold.
    static func encode(_ report: ValidatedAnalysisReport?) -> (json: Data?, version: Int) {
        guard let report else { return (nil, prose) }
        do {
            return (try JSONEncoder().encode(report), validatedReportV1)
        } catch {
            logger.error("Analysis report not encoded, stored as prose: \(error, privacy: .public)")
            return (nil, prose)
        }
    }

    /// The report stored as `json` in format `version`, or `nil` when the row
    /// is prose, the version is unknown, or the JSON does not decode.
    static func decode(_ json: Data?, version: Int) -> ValidatedAnalysisReport? {
        guard version != prose, let json else { return nil }
        guard version == validatedReportV1 else {
            logger.error("Analysis report in unknown format \(version, privacy: .public), shown as prose")
            return nil
        }
        do {
            return try JSONDecoder().decode(ValidatedAnalysisReport.self, from: json)
        } catch {
            logger.error("Analysis report not decoded, shown as prose: \(error, privacy: .public)")
            return nil
        }
    }
}
