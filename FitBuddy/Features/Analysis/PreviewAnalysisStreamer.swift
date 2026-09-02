#if DEBUG
import Foundation

/// Canned answer for SwiftUI previews, so the analysis screen can be driven
/// through loading, streaming and result without a key or a network call
/// (#32).
struct PreviewAnalysisStreamer: AnalysisStreaming {
    let chunks: [String]
    /// Who the preview attributes the answer to, and — with more than one
    /// entry — the fallback chain it walks before getting there (#79).
    let providers: [LLMProvider]
    /// Pause between chunks, so a preview shows text growing rather than
    /// appearing at once.
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
                for chunk in chunks {
                    try await Task.sleep(for: delay)
                    continuation.yield(.text(chunk))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension PreviewAnalysisStreamer {
    /// A recommendation arriving sentence by sentence.
    static let recommendation = PreviewAnalysisStreamer(
        chunks: [
            "Across the last four weeks you trained 14 times. ",
            "Chest and back carry most of the volume, while legs appear in only 3 sessions. ",
            "Bench press has sat at 60 kg for five sessions at the same rep count — a clean overload signal. ",
            "Add 2.5 kg on your next session and keep the reps where they are. ",
            "Give legs a second slot in the week before you push upper-body volume further.",
        ],
        providers: [.claude],
        delay: .milliseconds(400)
    )

    /// The same recommendation, reached only after Claude gives way to Gemini —
    /// the provider badge and the fallback notice of #79.
    static let fallback = PreviewAnalysisStreamer(
        chunks: recommendation.chunks,
        providers: [.claude, .gemini],
        delay: .milliseconds(400)
    )

    /// A run that never answers, for the 30s cancel state.
    static let silent = PreviewAnalysisStreamer(chunks: [], providers: [.claude], delay: .seconds(600))
}
#endif
