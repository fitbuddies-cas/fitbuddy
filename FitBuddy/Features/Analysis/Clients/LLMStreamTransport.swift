import Foundation

/// The parts of a streaming LLM call that are identical for every provider:
/// sending the request, deciding whether it was accepted, and walking the SSE
/// `data:` lines of the response (#79).
///
/// All three providers speak Server-Sent Events over HTTP and answer the same
/// status codes with the same meaning, so only the request body and the shape
/// of each `data:` payload actually differ — those stay in the clients.
enum LLMStreamTransport {
    private static let dataLinePrefix = "data:"

    /// Sends `request` and returns its body lines, or throws if the provider
    /// never accepted it.
    ///
    /// Awaiting the response head before returning is what gives
    /// `LLMProviderClient` its accepted/rejected contract: `URLSession.bytes`
    /// resolves as soon as the headers arrive, so this validates without
    /// buffering a single token of the answer.
    static func send(_ request: URLRequest, on session: URLSession) async throws -> URLSession.AsyncBytes {
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            // A cancelled call (user tapped cancel) is not a connectivity
            // problem and must not surface as one — nor trigger a fallback.
            if error.isCancellation { throw error }
            throw InferenceServiceError.networkUnavailable
        }
        guard let http = response as? HTTPURLResponse else {
            throw InferenceServiceError.invalidResponse
        }
        try validate(http)
        return bytes
    }

    /// The payload of every SSE `data:` line in `bytes`, with other lines
    /// (`event:`, `id:`, keep-alive blanks) skipped.
    static func dataPayloads(of bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix(dataLinePrefix) else { continue }
                        // SSE permits `data:value` without the space `data: value`
                        // shows in every example — trim rather than assume the
                        // space is always there.
                        continuation.yield(
                            line.dropFirst(dataLinePrefix.count).trimmingCharacters(in: .whitespaces)
                        )
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Maps a response status onto the failure the analysis screen explains.
    /// Identical across the three providers, which all use the standard
    /// meanings of 401 / 429 / 5xx.
    static func validate(_ http: HTTPURLResponse) throws {
        switch http.statusCode {
        case 200...299:
            return
        case 401, 403:
            // 403 shares the 401 bucket on purpose: Google answers a rejected
            // API key with `403 PERMISSION_DENIED`, which for the user is the
            // same problem as Anthropic's 401 — the key is not usable.
            throw InferenceServiceError.unauthorized
        case 429:
            throw InferenceServiceError.rateLimited(retryAfter: retryAfter(from: http))
        case 500...599:
            throw InferenceServiceError.serviceUnavailable
        default:
            throw InferenceServiceError.unexpectedStatus(http.statusCode)
        }
    }

    private static func retryAfter(from http: HTTPURLResponse) -> TimeInterval? {
        guard let raw = http.value(forHTTPHeaderField: "Retry-After") else { return nil }
        return TimeInterval(raw.trimmingCharacters(in: .whitespaces))
    }
}
