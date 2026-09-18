import Foundation

/// How much detail the prompt is built at — one rung of the degradation
/// ladder `AnalysisPromptBudget` picks (TD-1, US-15 AC8, #187).
///
/// Every cut is a list getting shorter, never a figure getting vaguer: the
/// window totals, the per-domain headline figures, the muscle split and the
/// last-seven-days line are the same at every rung, because they are what the
/// recommendation and the report validation (#175, #186) are built on. What
/// degrades is the tail of the lists, where a row costs tokens and adds
/// nothing the aggregates above it do not already carry. Each cut names
/// itself in the prompt, in the "(N … omitted)" form #173 established, so the
/// model reads a shortened list as shortened rather than as the whole window.
///
/// ## The ladder, and how it maps onto #187's
///
/// The issue asks for four steps. Two of them describe a prompt that no
/// longer exists — #183 rebuilt the endurance half as an aggregate and the
/// comparison windows as headline figures — so they are already true at
/// **every** rung and cost nothing to honour:
///
/// | #187's step | Here |
/// |---|---|
/// | 1. cardio session list → weekly aggregate | already so: `EndurancePromptSection` lists no session, only window totals, per-sport rows and per-week rows (#183) |
/// | 2. strength session list capped at 20 | rung 1 |
/// | 3. Exercises section capped at 6 | rung 2 |
/// | 4. comparison window headline figures only | already so: `comparisonSection` in both domains is four lines (#183) |
///
/// Rung 3 is this type's own addition, for the case the issue's steps cannot
/// reach: a widened 13-week window renders thirteen per-week rows in each
/// domain, and those are the last long list left once the two session lists
/// are capped.
///
/// ## Why the exercise cap travels with the prompt
///
/// `AnalysisReportEvidence` re-derives the listed exercises to check a
/// progression card against them (#175). If the prompt listed six and the
/// check knew ten, a card could be validated against an exercise the model
/// was never shown — the one thing a budget must not cause. The cap is
/// therefore carried on `AnalysisPrompt` and handed to
/// `AnalysisPromptBuilder.listedExercises(…)` with the reads (#178), so the
/// section and its validation are one list by construction.
struct AnalysisPromptDetail: Equatable, Sendable {
    /// Sessions the strength session list names individually.
    let listedSessions: Int

    /// Movements the Exercises section lists — and, with it, the movements a
    /// progression card may be validated against.
    let listedExercises: Int

    /// Weeks the per-week rows of both domains cover, newest first, or `nil`
    /// for every week of the window.
    let listedWeeks: Int?

    /// The prompt as #173 to #186 built it: nothing is given up.
    static let full = AnalysisPromptDetail(
        listedSessions: AnalysisPromptBuilder.maxListedSessions,
        listedExercises: AnalysisPromptBuilder.maxListedExercises,
        listedWeeks: nil
    )

    /// The rungs, in order. The first one that fits the budget is the prompt
    /// that is sent; when none does, the last one is — the ladder is what the
    /// app gives up, not a reason to refuse an analysis, and at a sixteenth of
    /// the smallest context window there is room to spare either way.
    static let ladder: [AnalysisPromptDetail] = [
        .full,
        AnalysisPromptDetail(listedSessions: 20, listedExercises: full.listedExercises, listedWeeks: nil),
        AnalysisPromptDetail(listedSessions: 20, listedExercises: 6, listedWeeks: nil),
        AnalysisPromptDetail(listedSessions: 20, listedExercises: 6, listedWeeks: 4),
    ]

    /// Whether this rung is the untouched prompt — what a test asserting "a
    /// Hevy-only window is unchanged" reads.
    var isFull: Bool { self == .full }

    /// Which per-week rows a domain renders, newest first, and the line that
    /// names the weeks it left out.
    ///
    /// One helper for both domains rather than the same arithmetic twice: the
    /// strength and the endurance half have to cut at the same week, or the
    /// two breakdowns of one window would describe different spans and the
    /// model would have no way to tell.
    ///
    /// - Returns: The week indices to render — 0 is the week ending on the
    ///   reference day — and a footer, or `nil` when every week is rendered
    ///   and there is nothing to announce.
    func weekRows(in window: AnalysisWindow) -> (indices: Range<Int>, footer: String?) {
        guard let listedWeeks, listedWeeks < window.weeks else { return (0..<window.weeks, nil) }
        let omitted = window.weeks - listedWeeks
        return (
            0..<listedWeeks,
            "(\(CountFormatter.labelled(omitted, singular: "earlier week")) in this window "
                + "omitted; the totals above cover all \(window.weeks) weeks)"
        )
    }
}
