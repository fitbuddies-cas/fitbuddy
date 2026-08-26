import Foundation

/// Drives the on-demand AI analysis: builds the prompt from the local cache,
/// streams Claude's answer, and owns the 6h cooldown the user sees (US-3, #31).
///
/// Three things are published separately because they answer different
/// questions. `state` says what the screen shows right now, `cooldownMessage`
/// says when the next run is allowed, and `isTakingLong` says whether this run
/// has passed the 30s mark without a single token — the moment US-3 AC1 wants
/// the cancel button to appear.
///
/// The prompt is built from the cache only: an analysis never triggers a Hevy
/// sync, so a tap here cannot fail on connectivity the dashboard already
/// handles.
@MainActor
final class AnalysisViewModel: ObservableObject {
    /// How long a run may go without a first token before the screen offers to
    /// cancel it (US-3 AC1). Not a deadline: the request keeps running, and
    /// `URLSession`'s own idle timeout still applies underneath. Killing a slow
    /// but healthy stream automatically would spend the cooldown on nothing —
    /// the user decides.
    static let defaultSlowThreshold: TimeInterval = 30

    @Published private(set) var state: AnalysisState = .idle
    /// `"Next analysis available in 5h 12m"`, or `nil` while a run is allowed.
    @Published private(set) var cooldownMessage: String?
    /// Whether the running call has passed `slowThreshold` without answering.
    /// Cleared as soon as the first token arrives, and on every state change
    /// out of a running state.
    @Published private(set) var isTakingLong = false
    /// The verdict the user gave on the recommendation currently on screen, or
    /// `nil` while none was given (US-3 AC9). Reset with every new run: a
    /// rating belongs to the recommendation it was given for.
    @Published private(set) var feedback: AnalysisFeedback?

    /// Whether tapping "Analyse" can start a run right now.
    var canStartAnalysis: Bool {
        !state.isRunning && cooldownMessage == nil
    }

    /// The run currently in flight, held so `cancel()` can stop it.
    private var runTask: Task<Void, Never>?
    /// Counts runs, so a superseded one cannot clean up after the run that
    /// replaced it. A finished run refreshes the cooldown before it lets go,
    /// and the user can start the next one during exactly that await.
    private var runID: UInt64 = 0
    /// Fires once `slowThreshold` has passed without a first token.
    private var slowTask: Task<Void, Never>?

    private let cache: WorkoutSummaryReading
    private let inference: AnalysisStreaming
    private let cooldown: AnalysisCooldownStore
    private let feedbackStore: AnalysisFeedbackStore
    private let calendar: Calendar
    private let now: () -> Date
    private let slowThreshold: TimeInterval
    private let tickInterval: TimeInterval

    /// - Parameters:
    ///   - cache: Read access to the cached window (`WorkoutStore` in the app).
    ///   - inference: The streaming call (`InferenceService` in the app).
    ///   - cooldown: The shared 6h window store — the same one the service
    ///     writes to, so the label and the service's own guard never disagree.
    ///   - feedbackStore: Where a "Helpful" / "Not helpful" tap is persisted —
    ///     locally, with no call behind it (US-3 AC9).
    ///   - now: Injectable clock, so windows and cooldown math are testable.
    ///   - slowThreshold: Injectable, so tests do not wait 30 real seconds.
    ///   - tickInterval: How often `trackCooldown()` refreshes the label.
    init(
        cache: WorkoutSummaryReading,
        inference: AnalysisStreaming,
        cooldown: AnalysisCooldownStore = AnalysisCooldownStore(),
        feedbackStore: AnalysisFeedbackStore = AnalysisFeedbackStore(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        slowThreshold: TimeInterval = AnalysisViewModel.defaultSlowThreshold,
        tickInterval: TimeInterval = 60
    ) {
        self.cache = cache
        self.inference = inference
        self.cooldown = cooldown
        self.feedbackStore = feedbackStore
        self.calendar = calendar
        self.now = now
        self.slowThreshold = slowThreshold
        self.tickInterval = tickInterval
    }

    // MARK: - Run

    /// Runs one analysis: cache read → prompt → stream → result.
    ///
    /// Never throws. Every failure lands in `state`, so the screen always has
    /// something to show and the button always comes back (#31 AC1). A second
    /// call while one is running is ignored rather than queued — the user
    /// tapping twice must not buy two analyses.
    func start() async {
        guard !state.isRunning else { return }

        await refreshCooldown()
        if let availableAt = await cooldown.activeCooldown(now: now()) {
            // Checked here as well as inside `InferenceService`: the button is
            // already disabled, but a stale label plus a fast tap must produce
            // an explanation, not a silent no-op.
            state = .error(.cooldownActive(availableAt: availableAt))
            return
        }

        feedback = nil
        runID &+= 1
        let id = runID
        let task = Task { await performAnalysis(id) }
        runTask = task
        await task.awaitingCancellation()
    }

    /// Stops the running call — the cancel button of US-3 AC1.
    ///
    /// Returns to `.idle` rather than keeping the half-written text: a
    /// recommendation cut off mid-sentence is not a recommendation, and
    /// presenting one as a result would be worse than showing none. The
    /// cooldown may still have started, so `cooldownMessage` explains why the
    /// button does not immediately come back.
    func cancel() {
        guard state.isRunning else { return }
        runTask?.cancel()
        runTask = nil
        stopSlowTimer()
        state = .idle
    }

    /// Clears a finished run, so the screen goes back to the analysis button.
    func reset() {
        guard !state.isRunning else { return }
        state = .idle
    }

    // MARK: - Feedback

    /// Records the user's verdict on the recommendation on screen (US-3 AC9).
    ///
    /// Only meaningful while a finished recommendation is showing: rating a
    /// spinner or an error message would attach the verdict to something the
    /// user never read. Purely local — there is no request behind this tap.
    func submitFeedback(_ feedback: AnalysisFeedback) async {
        guard case .result = state else { return }
        // Published first: the button has to look selected on the same run
        // loop as the tap, not after the store's actor hop.
        self.feedback = feedback
        await feedbackStore.record(feedback, at: now())
    }

    private func performAnalysis(_ id: UInt64) async {
        state = .loading
        startSlowTimer()

        guard let prompt = await buildPrompt() else { return await finish(id) }

        var text = ""
        do {
            let stream = try await inference.streamAnalysis(systemPrompt: prompt.system, userPrompt: prompt.user)
            for try await chunk in stream {
                try Task.checkCancellation()
                // The first token is the answer arriving: the slow hint has
                // served its purpose, whatever the rest of the stream costs.
                stopSlowTimer()
                text += chunk
                state = .streaming(text)
            }
            guard !Task.isCancelled else { return await finish(id) }
            // A stream that ends without a single token is not an empty
            // recommendation — it is a response this version could not read.
            state = text.isEmpty ? .error(.unreadableResponse) : .result(text)
        } catch {
            // A cancelled run already published `.idle` in `cancel()`; the
            // error here is only the echo of that, and must not overwrite it.
            guard !Task.isCancelled, !error.isCancellation else { return await finish(id) }
            state = .error(AnalysisFailure(analysisError: error))
        }
        await finish(id)
    }

    /// Reads the window and builds the prompt, or publishes the reason it
    /// could not. `nil` means the run is over.
    private func buildPrompt() async -> AnalysisPrompt? {
        let reference = now()
        do {
            let summaries = try await cache.workoutSummaries(
                since: AnalysisWindow.previousStart(endingAt: reference, calendar: calendar)
            )
            guard !Task.isCancelled else { return nil }

            // The comparison window may well be empty — that is a break, and
            // the prompt says so. An empty *recent* window is different: there
            // is nothing to analyse, and paying Claude to say so is waste.
            let recentStart = AnalysisWindow.start(endingAt: reference, calendar: calendar)
            guard summaries.contains(where: { $0.startTime >= recentStart }) else {
                state = .error(.noTrainingData)
                return nil
            }
            return AnalysisPromptBuilder.make(summaries: summaries, now: reference, calendar: calendar)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return nil }
            state = .error(.cacheUnavailable)
            return nil
        }
    }

    /// Ends a run: the slow hint goes, and the cooldown label is re-read from
    /// the store — including after a cancellation, where Claude may already
    /// have been billed and the window already started.
    private func finish(_ id: UInt64) async {
        // Superseded: the user started a new run while this one was letting
        // go. Its timer and its task handle belong to that run now.
        guard id == runID else { return }
        stopSlowTimer()
        runTask = nil
        // A run cancelled from outside — SwiftUI tearing down the `.task` that
        // called `start()` — never went through `cancel()`, so nothing has
        // published a resting state yet. Without this the screen would come
        // back still spinning, with no request behind it (#31 AC1).
        if Task.isCancelled && state.isRunning {
            state = .idle
        }
        await refreshCooldown()
    }

    // MARK: - Slow-run hint

    private func startSlowTimer() {
        slowTask?.cancel()
        isTakingLong = false
        let threshold = slowThreshold
        slowTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(threshold))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            // Only while nothing has arrived: a stream already producing text
            // is slow but visibly alive, and does not need the hint.
            guard case .loading = self.state else { return }
            self.isTakingLong = true
        }
    }

    private func stopSlowTimer() {
        // Called for every chunk of the stream: without this, each token would
        // publish an `isTakingLong` change nothing is listening for.
        guard slowTask != nil || isTakingLong else { return }
        slowTask?.cancel()
        slowTask = nil
        isTakingLong = false
    }

    // MARK: - Cooldown

    /// Recomputes `cooldownMessage` from the stored timestamp.
    func refreshCooldown() async {
        // One reading of the clock for both, so the label can never be built
        // against a different instant than the window was checked with.
        let reference = now()
        let availableAt = await cooldown.activeCooldown(now: reference)
        cooldownMessage = CooldownFormatter.message(until: availableAt, now: reference)
    }

    /// Keeps the cooldown label counting down while the screen is on display —
    /// the analysis view's `.task`.
    ///
    /// Runs until cancelled rather than until the window closes: the label has
    /// to appear the moment a run finishes, not only the next time the screen
    /// is opened.
    func trackCooldown() async {
        while !Task.isCancelled {
            await refreshCooldown()
            do {
                try await Task.sleep(for: .seconds(tickInterval))
            } catch {
                return
            }
        }
    }
}
