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
        var counts: [Key: Int] = [:]
        for intervention in logs.flatMap(\.interventions) {
            counts[Key(subject: intervention.subject, reason: intervention.reason), default: 0] += 1
        }
        rows = counts
            .map { AnalysisValidationTallyRow(subject: $0.key.subject, reason: $0.key.reason, count: $0.value) }
            .sorted { lhs, rhs in
                lhs.count != rhs.count ? lhs.count > rhs.count : lhs.id < rhs.id
            }
    }

    /// What the tally counts by: one part of the answer and one reason.
    private struct Key: Hashable {
        let subject: AnalysisInterventionSubject
        let reason: AnalysisInterventionReason
    }
}

#endif
