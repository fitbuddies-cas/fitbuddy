#if DEBUG
import Foundation

/// Canned answer for SwiftUI previews, so the analysis screen can be driven
/// through running and result without a key or a network call (#32).
///
/// Delivers the answer in one event, as `InferenceService` does since #174
/// (#178).
struct PreviewAnalysisStreamer: AnalysisStreaming {
    /// The answering provider's single event — `.report` or `.text` — or `nil`
    /// for a run that never answers.
    let answer: AnalysisEvent?
    /// Who the preview attributes the answer to, and — with more than one
    /// entry — the fallback chain it walks before getting there (#79).
    let providers: [LLMProvider]
    /// Pause before each handover and before the answer, so a preview shows
    /// the spinner rather than jumping straight to the result.
    let delay: Duration

    func streamAnalysis(systemPrompt: String, userPrompt: String) async throws -> AsyncThrowingStream<AnalysisEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                // Every provider but the last "fails" after its announcement,
                // which is what makes the handover visible in a preview.
                for provider in providers.dropLast() {
                    continuation.yield(.attempting(provider))
                    try await Task.sleep(for: delay)
                }
                if let answering = providers.last {
                    continuation.yield(.attempting(answering))
                }
                try await Task.sleep(for: delay)
                if let answer {
                    continuation.yield(answer)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension PreviewAnalysisStreamer {
    /// A structured recommendation. Previews have no exercise cache to
    /// validate the cards against, so the screen shows its summary (#178).
    static let recommendation = PreviewAnalysisStreamer(
        answer: .report(report),
        providers: [.claude],
        delay: .seconds(2)
    )

    /// A provider answering in prose — the fallback of US-14 AC5.
    static let prose = PreviewAnalysisStreamer(
        answer: .text(report.summary),
        providers: [.mistral],
        delay: .seconds(2)
    )

    /// The same recommendation, reached only after Claude gives way to Gemini —
    /// the provider badge and the fallback notice of #79.
    static let fallback = PreviewAnalysisStreamer(
        answer: recommendation.answer,
        providers: [.claude, .gemini],
        delay: .seconds(2)
    )

    /// A run that never answers, for the 30s cancel state.
    static let silent = PreviewAnalysisStreamer(answer: nil, providers: [.claude], delay: .seconds(600))

    /// The report behind `recommendation`.
    static let report = AnalysisReport(
        headline: "You're ready to progress.",
        verdict: .progress,
        cards: [
            .progression(
                exercise: "Bench Press (Barbell)",
                muscleGroup: "Chest",
                fromKg: 60,
                toKg: 62.5,
                reasoning: "Five sessions at 60 kg with the reps held."
            ),
            .imbalance(
                groupA: "Chest",
                perWeekA: 2.5,
                groupB: "Legs",
                perWeekB: 0.8,
                reasoning: "Give legs a second slot before adding upper-body volume."
            ),
        ],
        summary: """
            Across the last four weeks you trained 14 times, with chest and back \
            carrying most of the volume while legs appeared in only 3 sessions.

            - Add 2.5 kg on bench press next session and keep the reps
            - Give legs a second slot before you push upper-body volume further
            """
    )
}
#endif
