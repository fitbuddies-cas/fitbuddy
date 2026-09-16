import Foundation

/// What VoiceOver reads for each report card (#177).
///
/// Every card is one combined element, so it announces as a sentence rather
/// than as the chip, the struck-through figure and the arrow it is drawn
/// from. Spelled out here instead of letting SwiftUI concatenate the labels:
/// "60 kg 62.5 kg" does not say which way the weight moves, and "3×/wk" or
/// "Sessions / 7d" read aloud as symbols, not as a frequency.
enum AnalysisCardAccessibility {
    static func label(for card: AnalysisReportCard) -> String {
        switch card {
        case let .progression(exercise, muscleGroup, fromKg, toKg, reasoning):
            return """
            Increase. \(exercise), \(muscleGroup.displayName). \
            From \(AnalysisCardFormatter.weight(fromKg)) to \(AnalysisCardFormatter.weight(toKg)), \
            \(AnalysisCardFormatter.delta(fromKg: fromKg, toKg: toKg)). \(reasoning)
            """
        case let .recovery(reasoning, metrics):
            var figures = ["\(metrics.sessions) sessions in the last 7 days"]
            if let averageRPE = metrics.averageRPE {
                figures.append("average RPE \(AnalysisCardFormatter.rpe(averageRPE))")
            }
            figures.append("suggested rest \(metrics.suggestedRestHours) hours")
            return """
            Recovery. \(AnalysisCardFormatter.recoveryHeadline(metrics)) \(reasoning) \
            \(figures.joined(separator: ", ")).
            """
        case let .imbalance(groupA, perWeekA, groupB, perWeekB, reasoning):
            let bars = ImbalanceBar.bars(groupA: groupA, perWeekA: perWeekA, groupB: groupB, perWeekB: perWeekB)
            let frequencies = bars
                .map { "\($0.group.displayName) \(MuscleGroupFrequency.string($0.perWeek)) \($0.perWeek == 1 ? "time" : "times") per week" }
                .joined(separator: ", ")
            return "Imbalance. \(frequencies). \(reasoning)"
        case let .note(title, text):
            return "\(title). \(text)"
        }
    }
}
