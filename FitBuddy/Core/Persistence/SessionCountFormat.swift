import Foundation
import OSLog

/// How the session breakdown of an `AnalysisContext` is stored in
/// `AnalysisResult.sessionCountsJSON` and read back (US-15 AC4, #182): the
/// counts per source, which the context line names, the counts per domain, and
/// the part of those that reached the prompt, which the thin-data rule is
/// judged on.
///
/// One JSON blob rather than one integer column per source: the set of sources
/// grows (Hevy, then Strava, then Polar, ADR-6), and a schema version per
/// connector would make adding a source a store migration on every installed
/// device. All three maps are keyed by raw value, which is the same wire form
/// `Activity` already travels in, so a fourth connector is a new key and not a
/// new column.
///
/// The maps live in one blob because they describe the same sessions and only
/// mean anything together — a row cannot end up with the sources of one run
/// and the domains of another.
///
/// Read it through `decode(_:fallbackSessionCount:)`, never through
/// `JSONDecoder` directly: a row written before #182 has no such column, and
/// what it means is not "no sessions" but "all of them Hevy's".
enum SessionCountFormat {
    private static let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "SessionCountFormat")

    /// The stored shape. A struct rather than a bare dictionary so the maps
    /// keep their names in the file: a blob whose keys are read positionally
    /// is unreadable the first time it has to be debugged.
    private struct Stored: Codable {
        var sources: [String: Int]
        /// Absent on a row written by a build that counted sources only — the
        /// domains are then read off the sources, as that build meant them.
        var domains: [String: Int]?
        /// Absent where every counted session reached the prompt, which is
        /// what a row written before that distinction meant.
        var analysed: [String: Int]?
    }

    /// What a stored row says about its basis.
    enum Counts: Equatable {
        /// The breakdown as stored, or the pre-#182 reading of a row without
        /// one. `domains` and `analysed` are `nil` where the row did not
        /// record them, and the caller derives them.
        case breakdown(
            sources: [ConnectorSource: Int],
            domains: [AnalysisDomain: Int]?,
            analysed: [AnalysisDomain: Int]?
        )
        /// The blob could not be trusted, so only the row's own total is
        /// known. Deliberately not "all of them Hevy's": that reading is the
        /// truth for a row written *before* #182 and a guess for a row whose
        /// breakdown went bad, and a basis of three lifts and twenty runs must
        /// not come back as "23 Hevy sessions".
        case unattributed(Int)
    }

    /// The bytes to store for `context` — `nil` when there is nothing to store
    /// or the maps cannot be encoded. A row without them falls back to the
    /// single `sessionCount` column, which is written either way, so the
    /// context line survives the loss with a bare total instead of nothing.
    static func encode(_ context: AnalysisContext) -> Data? {
        let stored = Stored(
            sources: raw(context.sessionCounts),
            domains: raw(context.domainCounts),
            analysed: raw(context.analysedCounts)
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
    ///   single total every row has carried since #36.
    ///
    /// Three outcomes, and the difference between them matters:
    ///
    /// - **No blob.** Every analysis before #182 was built from Hevy sessions
    ///   alone — `AnalysisPromptBuilder.strengthSessions(in:)` dropped
    ///   everything else — so the total belongs to Hevy, and the row renders
    ///   exactly the line it was shown with.
    /// - **A blob this build can read.** Taken as stored; a map the row did
    ///   not record is left to the caller to derive.
    /// - **A blob it cannot.** Bytes that do not decode, or a key no
    ///   `ConnectorSource` or `AnalysisDomain` answers to — a row from a build
    ///   with a fourth connector. The row keeps its total and claims nothing
    ///   about where those sessions came from. Dropping just the unknown key
    ///   would be worse: the remaining counts would render as the whole basis
    ///   and quietly understate it.
    static func decode(_ json: Data?, fallbackSessionCount: Int) -> Counts {
        guard let json else { return hevyOnly(fallbackSessionCount) }
        do {
            let stored = try JSONDecoder().decode(Stored.self, from: json)
            guard
                let sources = map(stored.sources, to: ConnectorSource.init(rawValue:)),
                let domains = optionalMap(stored.domains, to: AnalysisDomain.init(rawValue:)),
                let analysed = optionalMap(stored.analysed, to: AnalysisDomain.init(rawValue:))
            else {
                logger.error("Session counts name something this build does not know, read as a total")
                return .unattributed(max(0, fallbackSessionCount))
            }
            return .breakdown(sources: sources, domains: domains, analysed: analysed)
        } catch {
            logger.error("Session counts not decoded, read as a total: \(error, privacy: .public)")
            return .unattributed(max(0, fallbackSessionCount))
        }
    }

    private static func raw<Key: RawRepresentable>(
        _ counts: [Key: Int]
    ) -> [String: Int] where Key.RawValue == String {
        Dictionary(uniqueKeysWithValues: counts.map { ($0.key.rawValue, $0.value) })
    }

    /// The mapped counts, or `nil` as soon as one key has no case — the map is
    /// then untrustworthy as a whole, not one entry short.
    private static func map<Key: Hashable>(
        _ raw: [String: Int],
        to key: (String) -> Key?
    ) -> [Key: Int]? {
        var mapped: [Key: Int] = [:]
        for (rawKey, value) in raw {
            guard let mappedKey = key(rawKey) else { return nil }
            mapped[mappedKey] = value
        }
        return mapped
    }

    /// `.some(nil)` for a map the row did not record, `nil` for one it did
    /// record and this build cannot read.
    private static func optionalMap<Key: Hashable>(
        _ raw: [String: Int]?,
        to key: (String) -> Key?
    ) -> [Key: Int]?? {
        guard let raw else { return .some(nil) }
        return map(raw, to: key).map { .some($0) }
    }

    private static func hevyOnly(_ sessionCount: Int) -> Counts {
        .breakdown(
            sources: sessionCount > 0 ? [.hevy: sessionCount] : [:],
            domains: nil,
            analysed: nil
        )
    }
}
