import Foundation
import OSLog

/// How an `AnalysisSendConfirmation` is stored in
/// `AnalysisResult.sendConfirmationJSON` and read back (US-3 AC12, #268).
///
/// One JSON blob rather than three columns, like `SessionCountFormat`: the
/// three values only mean anything together — a timestamp without the list
/// it confirmed is not a confirmation — and a row cannot end up with the
/// date of one run and the providers of another.
///
/// Read it through `decode(_:)`, never through `JSONDecoder` directly: a row
/// written before V7 has no such column, and what that means is "the sheet
/// did not exist yet", which the history shows as no line at all.
enum AnalysisSendConfirmationFormat {
    private static let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "AnalysisSendConfirmationFormat")

    /// The stored shape. Providers travel as raw values, the same wire form
    /// `LLMPriorityStore` writes, so a fourth provider is a new value and not
    /// a new column.
    private struct Stored: Codable {
        var confirmedAt: Date
        var consentVersion: String
        var providers: [String]
    }

    /// The bytes to store for `confirmation` — `nil` when there is none, or
    /// when it cannot be encoded. The row then keeps its recommendation and
    /// shows no confirmation line rather than a wrong one.
    static func encode(_ confirmation: AnalysisSendConfirmation?) -> Data? {
        guard let confirmation else { return nil }
        let stored = Stored(
            confirmedAt: confirmation.confirmedAt,
            consentVersion: confirmation.consentVersion,
            providers: confirmation.providers.map(\.rawValue)
        )
        do {
            return try encoder.encode(stored)
        } catch {
            logger.error("Send confirmation not encoded: \(error, privacy: .public)")
            return nil
        }
    }

    /// The confirmation stored as `json`, or `nil` when the row has none,
    /// the bytes do not decode, or a provider in it is one this build does
    /// not know. The whole confirmation is dropped in that last case rather
    /// than the one name: a list missing a recipient would claim less was
    /// sent than the user confirmed.
    static func decode(_ json: Data?) -> AnalysisSendConfirmation? {
        guard let json else { return nil }
        do {
            let stored = try decoder.decode(Stored.self, from: json)
            var providers: [LLMProvider] = []
            for raw in stored.providers {
                guard let provider = LLMProvider(rawValue: raw) else {
                    logger.error("Send confirmation names a provider this build does not know; not shown")
                    return nil
                }
                providers.append(provider)
            }
            return AnalysisSendConfirmation(
                confirmedAt: stored.confirmedAt,
                consentVersion: stored.consentVersion,
                providers: providers
            )
        } catch {
            logger.error("Send confirmation not decoded; not shown: \(error, privacy: .public)")
            return nil
        }
    }

    /// ISO 8601 rather than the default seconds-since-2001 double: the blob
    /// is evidence, and a timestamp a person can read without the app is
    /// worth the extra bytes.
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
