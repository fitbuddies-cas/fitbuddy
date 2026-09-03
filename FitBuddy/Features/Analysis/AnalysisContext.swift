import Foundation

/// What the recommendation on screen actually rests on: which sources, which
/// period, how many sessions (US-6, #36).
///
/// The user cannot see the prompt, so without this line the recommendation is
/// an assertion they have to take on faith. Naming the data basis is what lets
/// them tell "the model read my last four weeks" from "the model read three
/// sessions and guessed" — and AC2 makes the second case say so out loud.
///
/// The window travels with the count rather than being assumed to be the
/// default: the fallback ladder of #87 widens it when the last four weeks are
/// empty, and a context line naming a period the analysis did not use would be
/// the opposite of transparency.
struct AnalysisContext: Equatable, Sendable {
    /// Sessions the analysis window holds — the sessions the prompt was built
    /// from, not everything in the cache.
    let sessionCount: Int
    /// The period actually analysed.
    let window: AnalysisWindow

    /// Below this many sessions in the window, the data basis is called thin
    /// (US-6 AC2).
    ///
    /// Five because the prompt compares the window with the equally long one
    /// before it and reports per-week volume: under roughly one session a week
    /// a single missed or extra workout moves every number the model reasons
    /// over, and a confident recommendation drawn from that reads far firmer
    /// than the data underneath it.
    static let thinDataThreshold = 5

    /// Whether the warning of US-6 AC2 belongs on screen.
    var isThin: Bool { sessionCount < Self.thinDataThreshold }

    /// The sources the analysed sessions came from.
    ///
    /// A constant for v0: Hevy is the only connector, so anything else would
    /// be a promise the app cannot keep. #33/#35 introduce the connector
    /// registry that turns this into a real lookup — the call site is here
    /// already so that it is one place to change, not five string literals in
    /// a view.
    var sources: [String] { ["Hevy"] }
}
