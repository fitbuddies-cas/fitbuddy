import Foundation

/// The app's own verdict, derived from the figures it computed itself
/// (US-16 AC3/AC6, #227).
///
/// **The specification is `docs/adr/ADR-014-verdict-regel-der-app.md`** — the
/// order of the stages, every threshold and the wording of the fourth class
/// are decided there, not here. The two numbers this file needs are read from
/// where the rest of the app already keeps them
/// (`RecoveryMetrics.recoveryTrainingDays`, `ExerciseProgression`), so there
/// is one plateau definition and one rest-day threshold in the product. Only
/// `minimumSessionsInWindow` is written down here, and ADR-014 §9 is where it
/// comes from.
///
/// Separate from `AnalysisReportValidator` on purpose (#227): the validator
/// checks cards against the cache, this decides what the analysis says. The
/// validator calls it and applies the result to the report.
///
/// Stage 5 of ADR-014 — the effort cap — is **not** here: it needs the effort
/// data of #241 and arrives with #246. Until then the tree runs without it,
/// which is why `recover` has exactly one trigger and that trigger counts rest
/// days.
enum AnalysisVerdictRule {
    /// Sessions the resolved window must hold before the app judges anything
    /// (ADR-014 stage 1). Below this no exercise can reach the points stage 2
    /// asks for, so there is nothing to decide.
    static let minimumSessionsInWindow = 4

    /// Why the rule answered as it did — what the `Why there's no verdict`
    /// note names (ADR-014 §6), and what #228 records next to the model's
    /// own choice.
    enum Reason: String, Codable, CaseIterable, Equatable, Sendable {
        /// Stage 0: six of the last seven days were training days.
        case restDays
        /// Stage 1: fewer than `minimumSessionsInWindow` sessions in the window.
        case tooFewSessions
        /// Stage 1: nothing in the last seven days belongs to this analysis.
        case noRecentSession
        /// Stages 2–4 do not exist under this profile — there is no estimated
        /// 1RM outside strength (ADR-014 §5).
        case noStrengthDomain
        /// Stage 2: no listed exercise has enough sessions to tell a plateau
        /// from progress.
        case plateauUndecidable
        /// Stage 3: more than half of the decidable exercises are plateaued.
        case plateauMajority
        /// Stage 4: a decidable, non-plateaued exercise set the window's best
        /// in its most recent session.
        case latestIsWindowBest
        /// Stage "else": decidable, no majority plateau, no new best.
        case noNewBest
    }

    /// The verdict and the stage that produced it.
    struct Outcome: Equatable, Sendable {
        let verdict: AnalysisVerdict
        let reason: Reason
    }

    /// The verdict for this evidence — ADR-014 §2, first stage that fires
    /// wins.
    ///
    /// Deterministic and free of the model's answer by construction: it reads
    /// nothing but `evidence`, which is what US-16 AC1 rests on.
    static func outcome(for evidence: AnalysisReportEvidence) -> Outcome {
        // Stage 0. Domain-blind, because a rest day is a rest day whatever it
        // was taken from (#184). It can force `recover` and never allow
        // `progress` — changing that is an requirements change to US-3 AC6,
        // not a tuning of this rule (ADR-014 §2).
        if evidence.recovery.needsRecovery {
            return Outcome(verdict: .recover, reason: .restDays)
        }

        // Stage 1.
        if evidence.sessionsInWindow < minimumSessionsInWindow {
            return Outcome(verdict: .insufficientData, reason: .tooFewSessions)
        }
        if evidence.sessionsInLastSevenDays == 0 {
            return Outcome(verdict: .insufficientData, reason: .noRecentSession)
        }

        // Stages 2–4 are statements about estimated 1RM series, which exist
        // for strength and nowhere else. Under "Endurance" they are absent,
        // not zero — so the rule says it has no verdict rather than falling
        // through to `hold`, and that profile cannot produce `progress` in v0
        // (ADR-014 §5, listed there as a known negative consequence).
        guard evidence.analysisProfile.covers(.strength) else {
            return Outcome(verdict: .insufficientData, reason: .noStrengthDomain)
        }

        // Stage 2. "Decidable" is `ListedExercise.isPlateauDecidable`, which
        // is `ExerciseProgression.isPlateauDecidable` for the same movement —
        // the plateau definition of US-9 AC2, stated in one place so the
        // product has one.
        let decidable = evidence.exercises.filter(\.isPlateauDecidable)
        guard !decidable.isEmpty else {
            return Outcome(verdict: .insufficientData, reason: .plateauUndecidable)
        }

        // Stage 3. Strictly more than half, so an even split is not a
        // majority.
        let plateaued = decidable.filter(\.isPlateaued).count
        if plateaued * 2 > decidable.count {
            return Outcome(verdict: .hold, reason: .plateauMajority)
        }

        // Stage 4.
        if decidable.contains(where: { !$0.isPlateaued && $0.latestIsWindowBest }) {
            return Outcome(verdict: .progress, reason: .latestIsWindowBest)
        }

        return Outcome(verdict: .hold, reason: .noNewBest)
    }
}
