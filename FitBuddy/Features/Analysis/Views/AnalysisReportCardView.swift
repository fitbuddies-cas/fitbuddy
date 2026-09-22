import SwiftUI

/// Picks the view for one card of a validated report (#177).
struct AnalysisReportCardView: View {
    let card: AnalysisReportCard

    var body: some View {
        switch card {
        case let .progression(exercise, muscleGroup, fromKg, toKg, reasoning):
            ProgressionCardView(
                exercise: exercise,
                muscleGroup: muscleGroup,
                fromKg: fromKg,
                toKg: toKg,
                reasoning: reasoning
            )
        case let .recovery(reasoning, metrics):
            RecoveryCardView(reasoning: reasoning, metrics: metrics)
        case let .imbalance(groupA, perWeekA, groupB, perWeekB, reasoning):
            ImbalanceCardView(
                groupA: groupA,
                perWeekA: perWeekA,
                groupB: groupB,
                perWeekB: perWeekB,
                reasoning: reasoning
            )
        case let .metric(label, from, to, unit, reasoning, source):
            MetricCardView(
                label: label,
                from: from,
                to: to,
                unit: unit,
                reasoning: reasoning,
                source: source
            )
        case let .interference(metrics, reasoning):
            InterferenceCardView(metrics: metrics, reasoning: reasoning)
        case let .note(title, text):
            NoteCardView(title: title, text: text)
        }
    }
}

#if DEBUG
#Preview {
    ScrollView {
        VStack(spacing: 10) {
            ForEach(Array(AnalysisReportSamples.progress.cards.enumerated()), id: \.offset) { item in
                AnalysisReportCardView(card: item.element)
            }
            AnalysisReportCardView(card: AnalysisReportSamples.recoveryCard)
            AnalysisReportCardView(card: AnalysisReportSamples.weeklyDistanceCard)
            AnalysisReportCardView(card: AnalysisReportSamples.interferenceCard)
            AnalysisReportCardView(card: AnalysisReportSamples.noteCard)
        }
        .padding(16)
    }
    .background(Color.fbBackground)
}
#endif
