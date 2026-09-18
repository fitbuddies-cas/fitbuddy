import Foundation

/// The "Show full analysis" disclosure under the cards (US-14 AC1, #170): its
/// copy, and whether it starts open.
///
/// Kept out of the view so the opening rule is tested, not just rendered.
enum AnalysisFullAnalysis {
    static let showTitle = "Show full analysis"
    static let hideTitle = "Hide full analysis"

    /// Card kinds that tell the user what to do: a load change, a rest, a
    /// group to even out. A note is not one — it is prose in a card.
    static let actionableKinds: Set<AnalysisCard.Kind> = [.progression, .recovery, .imbalance]

    /// Open when no card is actionable: with thin data the full analysis is
    /// the answer, and hiding it would leave a headline over one short lead.
    /// Closed otherwise, so the cards come first.
    static func startsExpanded(for cards: [AnalysisReportCard]) -> Bool {
        !cards.contains { actionableKinds.contains($0.kind) }
    }

    /// The toggle's visible title in either state.
    static func toggleTitle(isExpanded: Bool) -> String {
        isExpanded ? hideTitle : showTitle
    }

    /// What VoiceOver reads after the toggle's label.
    static func accessibilityValue(isExpanded: Bool) -> String {
        isExpanded ? "Expanded" : "Collapsed"
    }
}
