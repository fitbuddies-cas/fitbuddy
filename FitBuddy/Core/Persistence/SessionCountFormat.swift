import Foundation
import OSLog

/// How the session breakdown of an `AnalysisContext` is stored in
/// `AnalysisResult.sessionCountsJSON` and read back (US-15 AC4, #182): the
/// counts per source, which the context line names, and the counts per domain,
/// which the thin-data rule is applied to.
///
/// One JSON column rather than one integer column per source: the set of
/// sources grows (Hevy, then Strava, then Polar, ADR-6), and a schema version
/// per connector would make adding a source a store migration on every
/// installed device. Both maps are keyed by raw value, which is the same wire
/// form `Activity` already travels in, so a fourth connector is a new key and
/// not a new column.
///
/// Both maps in one blob rather than two columns, because they describe the
/// same sessions and only mean anything together — a row cannot end up with
/// the sources of one run and the domains of another.
///
/// Read it through `decode(_:fallbackSessionCount:)`, never through
/// `JSONDecoder` directly: a row written before #182 has no such column, and
/// what it means is not "no sessions" but "all of them Hevy's".
enum SessionCountFormat {
    private static let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "SessionCountFormat")

    /// The stored shape. A struct rather than a bare dictionary so the two
    /// maps keep their names in the file: a blob whose keys are read
    /// positionally is unreadable the first time it has to be debugged.
    private struct Stored: Codable {
        var sources: [String: Int]
        /// Absent on a row written by a build that counted sources only — the
        /// domains are then read off the sources, as that build meant them.
        var domains: [String: Int]?
    }

    /// The counts of a context, read back as they were stored.
    struct Counts: Equatable {
        var sources: [ConnectorSource: Int]
        var domains: [AnalysisDomain: Int]?
    }

    /// The bytes to store for `context` — `nil` when there is nothing to store
    /// or the maps cannot be encoded. A row without them falls back to the
    /// single `sessionCount` column, which is written either way, so the
    /// context line survives the loss with one source instead of none.
    static func encode(_ context: AnalysisContext) -> Data? {
        let stored = Stored(
            sources: Dictionary(
                uniqueKeysWithValues: context.sessionCounts.map { ($0.key.rawValue, $0.value) }
            ),
            domains: Dictionary(
                uniqueKeysWithValues: context.domainCounts.map { ($0.key.rawValue, $0.value) }
            )
        )
        guard !stored.sources.isEmpty else { return nil }
        do {
            return try JSONEncoder().encode(stored)
        } catch {
            logger.error("Session counts not encoded: \(error, privacy: .public)")
            return nil
        }
    }

    /// The counts stored as `json`, or the pre-#182 reading of the row.
    ///
    /// - Parameter fallbackSessionCount: `AnalysisResult.sessionCount`, the
    ///   single total every row has carried since #36. Used when the column is
    ///   absent or unreadable: every analysis before #182 was built from Hevy
    ///   sessions alone — `AnalysisPromptBuilder.strengthSessions(in:)` dropped
    ///   everything else — so attributing the total to Hevy restores exactly
    ///   the line that row was shown with, rather than losing it.
    ///
    /// A `nil` `domains` means "derive them from the sources", which is what
    /// `AnalysisContext.init(sessionCounts:window:profile:)` does. An unknown
    /// key in either map — a row written by a newer build with a fourth
    /// connector — is dropped rather than failing the read: the history stays
    /// open, minus a count this build has no name for.
    static func decode(_ json: Data?, fallbackSessionCount: Int) -> Counts {
        guard let json else { return fallback(fallbackSessionCount) }
        do {
            let stored = try JSONDecoder().decode(Stored.self, from: json)
            return Counts(
                sources: map(stored.sources, to: ConnectorSource.init(rawValue:), named: "source"),
                domains: stored.domains.map {
                    map($0, to: AnalysisDomain.init(rawValue:), named: "domain")
                }
            )
        } catch {
            logger.error("Session counts not decoded, read as Hevy only: \(error, privacy: .public)")
            return fallback(fallbackSessionCount)
        }
    }

    private static func map<Key: Hashable>(
        _ raw: [String: Int],
        to key: (String) -> Key?,
        named kind: String
    ) -> [Key: Int] {
        raw.reduce(into: [Key: Int]()) { counts, entry in
            guard let mapped = key(entry.key) else {
                logger.error("Session count for unknown \(kind, privacy: .public) dropped")
                return
            }
            counts[mapped] = entry.value
        }
    }

    private static func fallback(_ sessionCount: Int) -> Counts {
        Counts(sources: sessionCount > 0 ? [.hevy: sessionCount] : [:], domains: nil)
    }
}
