import Foundation

// Developer tooling: excluded from Release builds, so the validation log
// view never ships in a TestFlight binary. The log itself is captured and
// stored in every build (#228).
#if DEBUG

/// The hit rate over several runs (US-16 AC4, #228, for #229): how many
/// stored analyses carry a log, how many went through untouched, how often
/// the app overruled the model's verdict, and how often each intervention
/// occurred.
struct AnalysisValidationTally: Equatable, Sendable {
    /// Analyses with a validation log.
    let runs: Int
    /// Of those, the ones without any intervention.
    let cleanRuns: Int
    /// Of those, the ones whose verdict the app replaced.
    let overriddenVerdicts: Int
    /// Interventions per part and reason, most frequent first.
    let rows: [AnalysisValidationTallyRow]

    init(logs: [AnalysisValidationLog]) {
        runs = logs.count
        cleanRuns = logs.filter { $0.interventions.isEmpty }.count
        overriddenVerdicts = logs.filter(\.verdictOverridden).count
        var counts: [String: AnalysisValidationTallyRow] = [:]
        for intervention in logs.flatMap(\.interventions) {
            let key = AnalysisValidationTallyRow(subject: intervention.subject, reason: intervention.reason, count: 0).id
            let previous = counts[key]?.count ?? 0
            counts[key] = AnalysisValidationTallyRow(
                subject: intervention.subject,
                reason: intervention.reason,
                count: previous + 1
            )
        }
        rows = counts.values.sorted { lhs, rhs in
            lhs.count != rhs.count ? lhs.count > rhs.count : lhs.id < rhs.id
        }
    }
}

#endif
