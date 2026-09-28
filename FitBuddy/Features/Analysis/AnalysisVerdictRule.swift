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
/// Stage 5 of ADR-014 — the effort cap (#246) — runs after the first stage
/// that fired, per scale (ADR-015). It can only cap: a rising scale turns
/// `progress` into `hold`, never produces `recover`, and without any
/// qualified scale — the ordinary case — the tree answers exactly as it did
/// before stage 5 existed. `recover` still has exactly one trigger, and that
/// trigger counts rest days.
enum AnalysisVerdictRule {
    /// Sessions the resolved window must hold before the app judges anything
    /// (ADR-014 stage 1). Below this no exercise can reach the points stage 2
    /// asks for, so there is nothing to decide.
    static let minimumSessionsInWindow = 4

    /// Distinct weeks of the window an effort scale must carry a value in
    /// before stage 5 reads it — one of them the last seven days, which is a
    /// second, separate condition (ADR-014 §3.3). Provisional (ADR-014 §3,
    /// §9): set, not measured.
    static let effortQualifyingWeeks = 3

    /// Above this ratio of the last seven days' mean to the preceding weeks'
    /// mean, a scale is rising (ADR-014 §3.4, 130 %). Provisional.
    static let effortRisingRatio = 1.30

    /// Below this ratio a scale is falling (ADR-014 §3.4, 80 %). Provisional.
    static let effortFallingRatio = 0.80

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
        /// Stage 5 (#246): a qualified effort scale the profile reads is
        /// rising, so `progress` became `hold` — or, under "Endurance", the
        /// `insufficientData` that only said "no strength stages here" did.
        ///
        /// Appended, never renamed: the raw value is persisted in the
        /// validation log (#228).
        case effortRising
    }

    /// The verdict and the stage that produced it.
    struct Outcome: Equatable, Sendable {
        let verdict: AnalysisVerdict
        let reason: Reason
    }

    /// The verdict for this evidence — ADR-014 §2, first stage that fires
    /// wins, then the effort cap of stage 5.
    ///
    /// Deterministic and free of the model's answer by construction: it reads
    /// nothing but `evidence`, which is what US-16 AC1 rests on.
    static func outcome(for evidence: AnalysisReportEvidence) -> Outcome {
        capped(firstStageOutcome(for: evidence), evidence: evidence)
    }

    /// The trend of `series`, or `nil` when the scale does not qualify
    /// (ADR-014 §3.3): fewer than `effortQualifyingWeeks` distinct weeks with
    /// a value, or none in the last seven days. An unqualified scale is
    /// ignored, never filled in.
    ///
    /// Direction only, never level (ADR-014 §3.1): the scale is compared with
    /// its own preceding weeks and with nothing else.
    static func trend(of series: EffortSeries) -> EffortTrend? {
        guard series.weeksWithValues >= effortQualifyingWeeks,
              let recent = series.lastSevenDaysMean,
              let preceding = series.precedingWeeksMean,
              preceding > 0
        else { return nil }
        let ratio = recent / preceding
        if ratio > effortRisingRatio { return .rising }
        if ratio < effortFallingRatio { return .falling }
        return .stable
    }

    /// Stage 5 (ADR-014 §2, §3.5): effort only caps.
    ///
    /// - `progress` becomes `hold` when any qualified scale the profile reads
    ///   is rising. The other scales are not set against it (§3.2).
    /// - Under "Endurance", the `insufficientData` that only says "stages 2–4
    ///   do not exist here" becomes `hold` on the same condition — the one
    ///   `hold` §5 allows that profile. A product decision on #246: the
    ///   `insufficientData` of the data gates (stages 1 and 2) says the data
    ///   carries nothing, and a rising scale does not change that.
    /// - `recover` stays `recover`; falling or stable effort does nothing.
    private static func capped(_ outcome: Outcome, evidence: AnalysisReportEvidence) -> Outcome {
        guard outcome.verdict == .progress || outcome.reason == .noStrengthDomain else { return outcome }
        let rising = evidence.effort.contains {
            $0.scale.isRead(under: evidence.analysisProfile) && trend(of: $0) == .rising
        }
        return rising ? Outcome(verdict: .hold, reason: .effortRising) : outcome
    }

    /// Stages 0–4 and the rest: the first stage that fires.
    private static func firstStageOutcome(for evidence: AnalysisReportEvidence) -> Outcome {
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
