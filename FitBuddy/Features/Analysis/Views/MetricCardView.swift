import SwiftUI

/// One figure of the training week, from where it stands to where the model
/// recommends it goes — in whatever unit that figure is measured in
/// (US-15 AC5, design 3.4c/3.4d, #186).
///
/// The generic card. Nothing in the layout is endurance- or strength-specific:
/// a weekly distance and a weekly volume are this card with a different
/// `MetricUnit`, which is what made a card type per sport unnecessary.
///
/// Colour follows the **meaning**, never the source and never the sign of the
/// number: the accent green marks a step that is an improvement in that unit —
/// more kilometres, a *lower* pace — and the warning orange one that asks for
/// less. The chip's words follow the number instead, because "Reduce" over a
/// pace would read as a step backwards.
struct MetricCardView: View {
    let label: String
    let from: Double
    let to: Double
    let unit: MetricUnit
    let reasoning: String
    /// The small muted label on the right of the header — "Run", "Strength",
    /// "Chest". Blank where the card has none, and then nothing is drawn: an
    /// empty label is a placeholder, and US-15 AC7 has none.
    let source: String

    private var improves: Bool { unit.isImprovement(from: from, to: to) }

    private var trimmedSource: String {
        source.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        FBCard(padding: 16) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    AnalysisCardChip(
                        symbol: AnalysisCardFormatter.metricChipSymbol(from: from, to: to),
                        title: AnalysisCardFormatter.metricChipTitle(from: from, to: to, unit: unit),
                        foreground: improves ? .fbAccentInk : .fbInk,
                        background: improves ? .fbAccentSoft : .fbWarnSoft,
                        border: improves ? .fbAccentBorder : .fbWarn.opacity(0.25)
                    )
                    if !trimmedSource.isEmpty {
                        Spacer(minLength: 8)
                        Text(trimmedSource)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.fbMuted)
                    }
                }
                .padding(.bottom, 6)

                Text(label)
                    .font(.fbTitle)
                    .tracking(-0.3)
                    .foregroundStyle(Color.fbInk)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    // Every figure is optional at this point only in the type
                    // system: the validator refused the card unless the unit
                    // could state both of them. A cell that cannot be written
                    // is left out rather than filled (US-15 AC7).
                    if let start = unit.display(from) {
                        Text(start)
                            .font(.subheadline)
                            .strikethrough()
                            .foregroundStyle(Color.fbMuted)
                        Image(systemName: "arrow.right")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color.fbMuted)
                    }
                    if let target = unit.display(to) {
                        Text(target)
                            .font(.title2.weight(.bold))
                            .tracking(-0.5)
                            .foregroundStyle(improves ? Color.fbAccent : Color.fbWarn)
                    }
                    if let delta = unit.delta(from: from, to: to) {
                        Spacer(minLength: 8)
                        Text(delta)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.fbMuted)
                    }
                }
                .fbTabularNumbers()
                .padding(.top, 10)

                Divider()
                    .overlay(Color.fbDivider)
                    .padding(.top, 10)

                Text(reasoning)
                    .font(.footnote)
                    .foregroundStyle(Color.fbInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            AnalysisCardAccessibility.label(
                for: .metric(
                    label: label,
                    from: from,
                    to: to,
                    unit: unit,
                    reasoning: reasoning,
                    source: source
                )
            )
        )
        .accessibilityIdentifier(AccessibilityID.Analysis.metricCard)
    }
}

#if DEBUG
/// Design 3.4c: the Endurance profile — km and min/km, not a kilogram in
/// sight.
#Preview("Endurance") {
    VStack(spacing: 10) {
        MetricCardView(
            label: "Weekly distance",
            from: 32,
            to: 35,
            unit: .kilometers,
            reasoning: "32 km held for three weeks at an unchanged easy heart rate — room for roughly 10 % more.",
            source: "Run"
        )
        MetricCardView(
            label: "Easy pace",
            from: 6.0,
            to: 5 + 20.0 / 60,
            unit: .minutesPerKilometer,
            reasoning: "The easy runs have drifted quick; hold them a little slower while the distance goes up.",
            source: "Run"
        )
    }
    .padding(16)
    .background(Color.fbBackground)
}

/// The same card asking for less, and one with no source label at all.
#Preview("Reduce") {
    VStack(spacing: 10) {
        MetricCardView(
            label: "Mean heart rate",
            from: 152,
            to: 148,
            unit: .beatsPerMinute,
            reasoning: "Run the easy sessions a little easier so the lifting days start fresher.",
            source: "Run"
        )
        MetricCardView(
            label: "Weekly volume",
            from: 12_400,
            to: 11_500,
            unit: .kilograms,
            reasoning: "Hold the volume down for a week while the running days move apart.",
            source: ""
        )
        MetricCardView(
            label: "Weekly training time",
            from: 6.5,
            to: 7,
            unit: .hours,
            reasoning: "Half an hour more, all of it in the long session.",
            source: "All sources"
        )
    }
    .padding(16)
    .background(Color.fbBackground)
}
#endif
