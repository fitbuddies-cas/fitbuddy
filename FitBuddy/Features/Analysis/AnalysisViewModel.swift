import Foundation
import OSLog

/// Drives the on-demand AI analysis: builds the prompt from the local cache,
/// streams the answer of whichever provider takes the call, and owns the 6h
/// cooldown the user sees (US-3, #31/#79).
///
/// Several things are published separately because they answer different
/// questions. `state` says what the screen shows right now, `attribution` says
/// who is answering it and who was asked before them, `cooldownMessage` says
/// when the next run is allowed, `resultAge` says how old the recommendation
/// on screen is, and `isTakingLong` says whether this run has passed the 30s
/// mark without a single token — the moment US-3 AC1 wants the cancel button
/// to appear.
///
/// A finished recommendation is persisted and restored (`restore()`), so it
/// survives an app restart: without it the 6h cooldown would leave a returning
/// user with a countdown and no answer to read (US-3 AC10, #97).
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
    /// Which provider is answering the run on screen, and whether the chain
    /// had to fall back to reach them (#79). `nil` before the first provider
    /// is tried, and whenever the screen is at rest.
    @Published private(set) var attribution: AnalysisAttribution?
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
    /// The window the analysis on screen actually covers. `.default` until a
    /// run resolves it, and widened by the fallback ladder when the last four
    /// weeks are empty (#87) — the UI names it only when it is not the
    /// default.
    @Published private(set) var window: AnalysisWindow = .default
    /// When the recommendation on screen was produced. Set by a finished run
    /// and by `restore()`; `nil` whenever no recommendation is showing (#97).
    @Published private(set) var generatedAt: Date?
    /// `generatedAt` as the screen prints it — `"2 h ago"`. Refreshed with the
    /// cooldown label, so a sheet left open does not keep claiming "just now".
    @Published private(set) var resultAge: String?

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
    /// Whether the user deliberately dismissed the stored recommendation by
    /// tapping "New analysis". Held so a reopened sheet does not put it right
    /// back — and cleared again as soon as the run they asked for is under
    /// way, because a run that then fails leaves the screen with nothing to
    /// read while the recommendation is still on disk (#97).
    private var didDismissStoredResult = false
    /// Guards `restore()` against overlapping itself: the view's `.task` and
    /// `dismissFailure()` can both ask for a restore, and the store read
    /// between them releases the main actor.
    private var isRestoring = false

    private let cache: WorkoutSummaryReading
    private let inference: AnalysisStreaming
    private let cooldown: AnalysisCooldownStore
    private let feedbackStore: AnalysisFeedbackStore
    private let resultStore: (any AnalysisResultStoring)?
    private let calendar: Calendar
    private let now: () -> Date
    private let slowThreshold: TimeInterval
    private let tickInterval: TimeInterval

    private let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "Analysis")

    /// - Parameters:
    ///   - cache: Read access to the cached window (`WorkoutStore` in the app).
    ///   - inference: The streaming call (`InferenceService` in the app).
    ///   - cooldown: The shared 6h window store — the same one the service
    ///     writes to, so the label and the service's own guard never disagree.
    ///   - feedbackStore: Where a "Helpful" / "Not helpful" tap is persisted —
    ///     locally, with no call behind it (US-3 AC9).
    ///   - resultStore: Where a finished recommendation is persisted, so it
    ///     survives an app restart (US-3 AC10). `nil` — the default — turns
    ///     persistence off, which is what SwiftUI previews need: they have no
    ///     `ModelContainer` to build a store over.
    ///   - now: Injectable clock, so windows and cooldown math are testable.
    ///   - slowThreshold: Injectable, so tests do not wait 30 real seconds.
    ///   - tickInterval: How often `trackCooldown()` refreshes the label.
    init(
        cache: WorkoutSummaryReading,
        inference: AnalysisStreaming,
        cooldown: AnalysisCooldownStore = AnalysisCooldownStore(),
        feedbackStore: AnalysisFeedbackStore = AnalysisFeedbackStore(),
        resultStore: (any AnalysisResultStoring)? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        slowThreshold: TimeInterval = AnalysisViewModel.defaultSlowThreshold,
        tickInterval: TimeInterval = 60
    ) {
        self.cache = cache
        self.inference = inference
        self.cooldown = cooldown
        self.feedbackStore = feedbackStore
        self.resultStore = resultStore
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
        // Claim the slot before the first await: an await releases the main
        // actor, so two taps landing in that window would otherwise both pass
        // the guard above and start a run each.
        state = .loading
        // Cleared before the cooldown branch below can return: that branch
        // publishes an error which `AnalysisErrorView` renders together with
        // the attribution, and the providers of the *previous* run have nothing
        // to do with a blocked one.
        attribution = nil

        if let availableAt = await refreshCooldown() {
            // Checked here as well as inside `InferenceService`: the button is
            // already disabled, but a stale label plus a fast tap must produce
            // an explanation, not a silent no-op.
            state = .error(.cooldownActive(availableAt: availableAt))
            return
        }
        // A `cancel()` that landed during the await above already published a
        // resting state; it wins over the run it stopped before it started.
        guard case .loading = state else { return }

        feedback = nil
        window = .default
        // The dismissal has served its purpose: the user asked for a new
        // analysis and is getting one. If this run fails, the screen falls
        // back to `.idle` with nothing on it, and the stored recommendation is
        // then the most useful thing it can offer again.
        didDismissStoredResult = false
        // The stored recommendation stays on disk until this run replaces it:
        // a run that ends in an error must not cost the user the last answer
        // they still had. Only the screen lets go of it here.
        clearResultAge()
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
        attribution = nil
        state = .idle
    }

    /// Clears a finished run, so the screen goes back to the analysis button.
    ///
    /// Two different taps land here. "New analysis" on a finished
    /// recommendation is a deliberate dismissal — the user wants the intro
    /// screen, and the stored recommendation must not come straight back.
    /// "Back" on an error is not: it leaves the screen empty, and
    /// `dismissFailure()` brings the stored recommendation back instead of
    /// leaving a countdown with nothing under it (#97).
    func reset() {
        guard !state.isRunning else { return }
        if case .result = state {
            didDismissStoredResult = true
        }
        attribution = nil
        feedback = nil
        window = .default
        clearResultAge()
        state = .idle
    }

    /// "Back" on the error screen: clears the failure and puts the stored
    /// recommendation back if there is one.
    ///
    /// Its own entry point rather than a branch inside `reset()`: the tap
    /// leaves the screen empty, and the restore behind it is asynchronous,
    /// which `reset()` — called straight from a SwiftUI button — is not.
    func dismissFailure() async {
        reset()
        await restore()
    }

    // MARK: - Restore

    /// Brings the last persisted recommendation back as the screen's landing
    /// state (US-3 AC10, #97).
    ///
    /// Called from `AnalysisView.task`, not from the dashboard: the dashboard
    /// drops this view model's state when the Hevy key is replaced (#91), and
    /// a restore racing that teardown would put the discarded account's
    /// recommendation straight back on screen.
    ///
    /// Does nothing while a run is in flight or a result is already showing —
    /// what is on screen is at least as current as what is on disk — and
    /// nothing while the user has dismissed the stored recommendation without
    /// a run having replaced it since.
    func restore() async {
        guard !didDismissStoredResult, !isRestoring else { return }
        // Claimed before the first await, like the run slot in `start()`.
        isRestoring = true
        defer { isRestoring = false }
        guard case .idle = state, let resultStore else { return }

        let stored: AnalysisResultSnapshot?
        do {
            stored = try await resultStore.latest()
        } catch {
            // Nothing to tell the user here: they asked for the analysis
            // screen, not for the recommendation, and the intro state they get
            // instead is a working screen rather than an error.
            logger.error("Stored analysis not readable: \(error, privacy: .public)")
            return
        }
        guard let stored else { return }
        // Re-checked after the awaits: the user can have started a run in the
        // meantime, and the restore must never overwrite it.
        guard case .idle = state else { return }

        state = .result(stored.text)
        window = stored.window
        generatedAt = stored.generatedAt
        refreshResultAge()
        // Only a verdict given after this recommendation was written can belong
        // to it. An older one rated a recommendation that no longer exists, and
        // showing it as selected would attribute the user's opinion to a text
        // they never saw.
        guard let last = await feedbackStore.lastFeedback(), last.date >= stored.generatedAt else {
            return
        }
        // Re-checked after that await as well: a run started in the meantime
        // has already published its own state with `feedback` cleared, and
        // assigning here would pre-select a verdict on a text the user has
        // not read yet.
        guard case .result(stored.text) = state else { return }
        feedback = last.feedback
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
        // `state` is already `.loading` — `start()` claimed the slot there.
        startSlowTimer()

        guard let prompt = await buildPrompt() else { return await finish(id) }

        var text = ""
        do {
            let stream = try await inference.streamAnalysis(systemPrompt: prompt.system, userPrompt: prompt.user)
            for try await event in stream {
                try Task.checkCancellation()
                switch event {
                case .attempting(let provider):
                    // A provider is taking over. Everything streamed so far
                    // came from one that has since failed, and showing it
                    // alongside the new answer would read as one recommendation
                    // written by two models — so it goes.
                    text = ""
                    if attribution != nil {
                        attribution?.append(provider)
                        // Back to the spinner: the new provider has not sent
                        // anything yet.
                        state = .loading
                        // And the slow hint with it: the first `.text` of the
                        // provider that gave way already stopped the timer, so
                        // without a restart here the cancel button of US-3 AC1
                        // never comes back while the new provider hangs.
                        startSlowTimer()
                    } else {
                        attribution = AnalysisAttribution(first: provider)
                    }
                case .text(let chunk):
                    // The first token is the answer arriving: the slow hint has
                    // served its purpose, whatever the rest of the stream costs.
                    stopSlowTimer()
                    text += chunk
                    state = .streaming(text)
                }
            }
            guard !Task.isCancelled else { return await finish(id) }
            // A stream that ends without a single token is not an empty
            // recommendation — it is a response this version could not read.
            if text.isEmpty {
                state = .error(.unreadableResponse(attribution?.provider))
            } else {
                state = .result(text)
                await persist(text)
            }
        } catch {
            // A cancelled run already published `.idle` in `cancel()`; the
            // error here is only the echo of that, and must not overwrite it.
            guard !Task.isCancelled, !error.isCancellation else { return await finish(id) }
            // The provider named is the last one the chain tried — the one whose
            // failure the user is actually looking at.
            state = .error(AnalysisFailure(analysisError: error, provider: attribution?.provider))
        }
        await finish(id)
    }

    /// Reads the window and builds the prompt, or publishes the reason it
    /// could not. `nil` means the run is over.
    private func buildPrompt() async -> AnalysisPrompt? {
        let reference = now()
        do {
            // Read wide enough for the widest rung of the ladder and its
            // comparison window; the cache returns what it has, and the
            // resolved window decides what of it is actually analysed.
            let summaries = try await cache.workoutSummaries(
                since: AnalysisWindow.widest.previousStart(endingAt: reference, calendar: calendar)
            )
            guard !Task.isCancelled else { return nil }

            // The comparison window may well be empty — that is a break, and
            // the prompt says so. An empty *recent* window widens the window
            // instead of failing: someone returning from a six-week break has
            // training worth analysing (#87). Only a cache with nothing in the
            // widest window at all is "no training data", and paying a provider
            // to say so would be waste.
            guard let window = AnalysisWindow.resolve(
                for: summaries,
                endingAt: reference,
                calendar: calendar
            ) else {
                state = .error(.noTrainingData)
                return nil
            }
            self.window = window
            return AnalysisPromptBuilder.make(
                summaries: summaries,
                window: window,
                now: reference,
                calendar: calendar
            )
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return nil }
            state = .error(.cacheUnavailable)
            return nil
        }
    }

    /// Writes the finished recommendation to disk, so it is still there after
    /// an app restart (US-3 AC10, #97).
    ///
    /// Only reached from the `.result` branch above: a cancelled, failed or
    /// unreadable run has nothing worth keeping, and overwriting the last good
    /// recommendation with it would cost the user an answer they already paid
    /// a provider for.
    ///
    /// A failing write is logged, not surfaced: the recommendation is on screen
    /// and readable, and an error banner over it would be about the next
    /// launch, not about anything the user can act on now.
    private func persist(_ text: String) async {
        let timestamp = now()
        generatedAt = timestamp
        refreshResultAge()
        guard let resultStore else { return }
        do {
            try await resultStore.save(text: text, generatedAt: timestamp, window: window)
        } catch {
            logger.error("Analysis not persisted: \(error, privacy: .public)")
        }
    }

    /// Ends a run: the slow hint goes, and the cooldown label is re-read from
    /// the store — including after a cancellation, where a provider may
    /// already have been billed and the window already started.
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

    /// Recomputes `cooldownMessage` from the stored timestamp and returns the
    /// instant the window ends, or `nil` while a run is allowed.
    ///
    /// Callers that need the decision as well as the label take it from here
    /// rather than asking the store again: one reading of the clock and one of
    /// the store, so message and decision can never describe different
    /// instants.
    @discardableResult
    func refreshCooldown() async -> Date? {
        let reference = now()
        let availableAt = await cooldown.activeCooldown(now: reference)
        cooldownMessage = CooldownFormatter.message(until: availableAt, now: reference)
        // Both labels age at the same rate and are driven by the same ticker,
        // so they are refreshed together against one reading of the clock.
        refreshResultAge(now: reference)
        // A cooldown message on screen outlives its reason otherwise: once the
        // window closes, the explanation is wrong and the button is back.
        if availableAt == nil, case .error(.cooldownActive) = state {
            state = .idle
        }
        return availableAt
    }

    // MARK: - Result age

    /// Re-renders `resultAge` from `generatedAt`.
    ///
    /// Reuses `SyncTimeFormatter`, which the sync banner already uses: the two
    /// timestamps say the same kind of thing, and a second formatter would
    /// drift from it.
    private func refreshResultAge(now reference: Date? = nil) {
        guard let generatedAt else {
            resultAge = nil
            return
        }
        resultAge = SyncTimeFormatter.relative(since: generatedAt, now: reference ?? now())
    }

    /// Takes the recommendation's timestamp off the screen. Does not touch the
    /// stored one — see `start()`.
    private func clearResultAge() {
        generatedAt = nil
        resultAge = nil
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
