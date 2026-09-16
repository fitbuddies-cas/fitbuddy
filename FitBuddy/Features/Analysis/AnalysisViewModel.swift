import Foundation
import OSLog

/// Drives the on-demand AI analysis: builds the prompt from the local cache,
/// streams the answer of whichever provider takes the call, and owns the short
/// lock between two runs (US-3, #31/#79/#117).
///
/// Several things are published separately because they answer different
/// questions. `state` says what the screen shows right now, `attribution` says
/// who is answering it and who was asked before them, `lockMessage` says
/// when the next run is allowed, `resultAge` says how old the recommendation
/// on screen is, and `isTakingLong` says whether this run has passed the 30s
/// mark without a single token — the moment US-3 AC1 wants the cancel button
/// to appear.
///
/// Every finished recommendation is persisted, and the newest one is restored
/// (`restore()`), so it survives an app restart and the ones before it stay
/// reachable on the history screen (US-3 AC10/AC11, #97/#117).
///
/// The prompt is built from the cache only: an analysis never triggers a Hevy
/// sync, so a tap here cannot fail on connectivity the dashboard already
/// handles.
@MainActor
final class AnalysisViewModel: ObservableObject {
    /// How long a run may go without a first token before the screen offers to
    /// cancel it (US-3 AC1). Not a deadline: the request keeps running, and
    /// `URLSession`'s own idle timeout still applies underneath. Killing a slow
    /// but healthy stream automatically would spend the user's tokens on
    /// nothing — the user decides.
    static let defaultSlowThreshold: TimeInterval = 30

    @Published private(set) var state: AnalysisState = .idle
    /// Which provider is answering the run on screen, and whether the chain
    /// had to fall back to reach them (#79). `nil` before the first provider
    /// is tried, and whenever the screen is at rest.
    @Published private(set) var attribution: AnalysisAttribution?
    /// `"New analysis available in 45s"`, or `nil` while a run is allowed.
    @Published private(set) var lockMessage: String?
    /// Whether the running call has passed `slowThreshold` without answering.
    /// Cleared as soon as the first token arrives, and on every state change
    /// out of a running state.
    @Published private(set) var isTakingLong = false
    /// What the analysis on screen rests on: how many sessions, over which
    /// period, from which sources (US-6, #36). `nil` until a run has resolved
    /// its window — before that there is no data basis to describe, and a
    /// guessed one would be worse than none.
    @Published private(set) var context: AnalysisContext?
    /// When the recommendation on screen was produced. Set by a finished run
    /// and by `restore()`; `nil` whenever no recommendation is showing (#97).
    @Published private(set) var generatedAt: Date?
    /// `generatedAt` as the screen prints it — `"2 h ago"`. Refreshed with the
    /// lock label, so a sheet left open does not keep claiming "just now".
    @Published private(set) var resultAge: String?
    /// Whether more than one analysis is stored, and the history is therefore
    /// worth opening (US-3 AC11, #117). With a single one the screen already
    /// shows it, and a link to a list of exactly that would be a detour.
    @Published private(set) var hasHistory = false

    /// Whether tapping "Analyse" can start a run right now.
    var canStartAnalysis: Bool {
        !state.isRunning && lockMessage == nil
    }

    /// The run currently in flight, held so `cancel()` can stop it.
    private var runTask: Task<Void, Never>?
    /// Counts runs, so a superseded one cannot clean up after the run that
    /// replaced it. A finished run refreshes the lock label before it lets
    /// go, and the user can start the next one during exactly that await.
    private var runID: UInt64 = 0
    /// Fires once `slowThreshold` has passed without a first token.
    private var slowTask: Task<Void, Never>?
    /// The ticker's current sleep, held so a lock that starts while the ticker
    /// is resting can cut that sleep short (#117).
    private var tickerSleep: Task<Void, Never>?
    /// Whether the user deliberately dismissed the stored recommendation by
    /// tapping "New analysis". Held so a reopened sheet does not put it right
    /// back — and cleared again as soon as the run they asked for is under
    /// way, because a run that then fails leaves the screen with nothing to
    /// read while the recommendation is still on disk (#97).
    ///
    /// Deliberately process-local: dismissing is not deleting, so it is not
    /// persisted, and an app restart brings the stored recommendation back.
    /// That is what US-3 AC10 asks for — the recommendation survives a
    /// restart — and "New analysis" is a request for a new run, not a request
    /// to throw the paid-for answer away.
    private var didDismissStoredResult = false
    /// The stored row the recommendation on screen came from, so a deletion in
    /// the history can tell whether it removed exactly this one (#117). `nil`
    /// whenever nothing persisted is showing — a preview without a store, or a
    /// run whose write failed.
    private var currentResultID: UUID?
    /// Guards `restore()` against overlapping itself: the view's `.task` and
    /// `dismissFailure()` can both ask for a restore, and the store read
    /// between them releases the main actor.
    private var isRestoring = false

    private let cache: WorkoutSummaryReading
    private let exerciseCache: (any ExerciseSummaryReading & ExerciseProgressionReading)?
    private let inference: AnalysisStreaming
    private let rateLimit: AnalysisRateLimitStore
    private let resultStore: (any AnalysisResultStoring)?
    private let calendar: Calendar
    private let now: () -> Date
    private let slowThreshold: TimeInterval
    private let tickInterval: TimeInterval
    private let restingTickInterval: TimeInterval

    private let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "Analysis")

    /// - Parameters:
    ///   - cache: Read access to the cached window (`WorkoutStore` in the app).
    ///   - exerciseCache: Per-exercise read access for the prompt's Exercises
    ///     section (#173) — `WorkoutStore` in the app, like `cache`. `nil` —
    ///     the default — builds the prompt without exercise data, which is
    ///     what SwiftUI previews get: the prompt then says there is none, and
    ///     the system prompt forbids naming a weight it was not given.
    ///   - inference: The streaming call (`InferenceService` in the app).
    ///   - rateLimit: The shared lock store — the same one the service writes
    ///     to, so the label and the service's own guard never disagree.
    ///   - resultStore: Where a finished recommendation is persisted, so it
    ///     survives an app restart (US-3 AC10). `nil` — the default — turns
    ///     persistence off, which is what SwiftUI previews need: they have no
    ///     `ModelContainer` to build a store over.
    ///   - now: Injectable clock, so windows and lock math are testable.
    ///   - slowThreshold: Injectable, so tests do not wait 30 real seconds.
    ///   - tickInterval: How often `trackLock()` refreshes the label while
    ///     the lock is running. One second, because a 60s lock counted down in
    ///     minute steps would never visibly move.
    ///   - restingTickInterval: The same, once no lock is active — only the
    ///     recommendation's age still changes, and it changes slowly.
    init(
        cache: WorkoutSummaryReading,
        exerciseCache: (any ExerciseSummaryReading & ExerciseProgressionReading)? = nil,
        inference: AnalysisStreaming,
        rateLimit: AnalysisRateLimitStore = AnalysisRateLimitStore(),
        resultStore: (any AnalysisResultStoring)? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        slowThreshold: TimeInterval = AnalysisViewModel.defaultSlowThreshold,
        tickInterval: TimeInterval = 1,
        restingTickInterval: TimeInterval = 60
    ) {
        self.cache = cache
        self.exerciseCache = exerciseCache
        self.inference = inference
        self.rateLimit = rateLimit
        self.resultStore = resultStore
        self.calendar = calendar
        self.now = now
        self.slowThreshold = slowThreshold
        self.tickInterval = tickInterval
        self.restingTickInterval = restingTickInterval
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
        // Cleared before the lock branch below can return: that branch
        // publishes an error which `AnalysisErrorView` renders together with
        // the attribution, and the providers of the *previous* run have nothing
        // to do with a blocked one.
        attribution = nil
        // Cleared before the lock branch below can return, too: that branch
        // publishes an error, and `dismissFailure()` then calls `restore()` to
        // put the stored recommendation back. Clearing this only on the path
        // that actually starts a run would leave a refused tap holding the flag
        // for the rest of the session — countdown on screen, recommendation
        // still on disk, unreachable until the app restarts (#97).
        didDismissStoredResult = false

        if let availableAt = await refreshLock() {
            // Checked here as well as inside `InferenceService`: the button is
            // already disabled, but a stale label plus a fast tap must produce
            // an explanation, not a silent no-op.
            state = .error(.lockActive(availableAt: availableAt))
            return
        }
        // A `cancel()` that landed during the await above already published a
        // resting state; it wins over the run it stopped before it started.
        guard case .loading = state else { return }

        currentResultID = nil
        context = nil
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
    /// lock may still have started, so `lockMessage` explains why the
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
        currentResultID = nil
        context = nil
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
    /// Refreshes the history entry point on the way, so a returning user sees
    /// the link to their earlier analyses without a run in between.
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
            // Two rather than one: the second row is all the toolbar link needs
            // to know, and reading the whole history to count it would load
            // twenty recommendations nobody asked to see.
            let newest = try await resultStore.recent(limit: 2)
            hasHistory = newest.count > 1
            stored = newest.first
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
        context = stored.context
        generatedAt = stored.generatedAt
        currentResultID = stored.id
        refreshResultAge()
    }

    /// Re-reads what the history holds, after the user has been in it (#117).
    ///
    /// Two things can have changed in there: whether a history still exists at
    /// all, and whether the recommendation on this screen is one of the rows
    /// the user swiped away. A deleted analysis must not stay on screen — it
    /// would be the one text in the app that "delete" did not remove — so the
    /// screen falls back to whatever is newest now, or to the intro.
    func refreshHistory() async {
        guard let resultStore else { return }
        let newest: [AnalysisResultSnapshot]
        do {
            newest = try await resultStore.recent(limit: 2)
        } catch {
            logger.error("Analysis history not readable: \(error, privacy: .public)")
            return
        }
        hasHistory = newest.count > 1
        guard case .result = state,
              let currentResultID,
              !newest.contains(where: { $0.id == currentResultID })
        else { return }
        reset()
        // `reset()` counts as a dismissal, but this one is not the user asking
        // for the intro screen — it is their deletion taking effect, and what
        // is left of the history belongs back on screen.
        didDismissStoredResult = false
        await restore()
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
                case .report(let report):
                    // Shown and stored as its prose summary until the cards
                    // have a screen (#177) and a stored format (#176); #178
                    // reworks this loop around the report.
                    stopSlowTimer()
                    text = report.summary
                    state = .streaming(text)
                }
            }
            guard !Task.isCancelled else { return await finish(id) }
            // A stream that ends without a single token is not an empty
            // recommendation — it is a response this version could not read.
            if text.isEmpty {
                state = .error(.unreadableResponse(attribution?.provider))
            } else {
                await persist(text)
                // Before `.result`, not after: `canStartAnalysis` reads
                // `lockMessage`, and a value still nil from before the run
                // makes `AnalysisResultView` offer "New analysis" for a run
                // that `start()` would immediately refuse — replacing the
                // recommendation that just arrived with a lock error. While
                // these awaits run the state stays `.streaming`, so the button
                // is never enabled in between.
                await refreshLock()
                // A `cancel()` during the awaits above already published a
                // resting state; it wins over the run it stopped.
                guard !Task.isCancelled else { return await finish(id) }
                state = .result(text)
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
            // Strava sessions are dropped right here, so the window ladder,
            // the context line and the prompt all describe the same strength
            // history (US-6 AC1) — a cache holding nothing but runs is "no
            // training data" for the analysis, not a window to widen.
            let summaries = AnalysisPromptBuilder.strengthSessions(
                in: try await cache.workoutSummaries(
                    since: AnalysisWindow.widest.previousStart(endingAt: reference, calendar: calendar)
                )
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
            let start = window.start(endingAt: reference, calendar: calendar)
            // Read before the context is published: a read that fails here
            // fails the run, and a failed run must not leave a data basis on
            // screen.
            let exercises = try await readExercises(since: start)
            guard !Task.isCancelled else { return nil }

            // Counted over the resolved window, not over everything the read
            // returned: the cache was read wide enough for the widest rung and
            // its comparison window, and reporting those sessions as the data
            // basis would overstate it by a factor of six.
            context = AnalysisContext(
                sessionCount: summaries.filter { $0.startTime >= start }.count,
                window: window
            )
            return AnalysisPromptBuilder.make(
                summaries: summaries,
                exercises: exercises.summaries,
                progressions: exercises.progressions,
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

    /// The movements of the analysed window, and the progression of each one
    /// the prompt lists (#173).
    ///
    /// Read over the resolved window, not over the wide read above: the
    /// Exercises section ranks by volume *in the window*, and a 26-week roll-up
    /// would rank by lifts the user may have long moved away from. Progressions
    /// are read only for the movements `AnalysisPromptBuilder` will list, so a
    /// window with forty exercises costs ten reads, not forty.
    private func readExercises(
        since start: Date
    ) async throws -> (summaries: [ExerciseSummary], progressions: [String: ExerciseProgression]) {
        guard let exerciseCache else { return ([], [:]) }
        let summaries = try await exerciseCache.exerciseSummaries(since: start)
        var progressions: [String: ExerciseProgression] = [:]
        for exercise in AnalysisPromptBuilder.promptedExercises(from: summaries) {
            guard !Task.isCancelled else { break }
            progressions[exercise.id] = try await exerciseCache.exerciseProgression(id: exercise.id, since: start)
        }
        return (summaries, progressions)
    }

    /// Appends the finished recommendation to the history, so it is still there
    /// after an app restart and the ones before it stay readable (US-3
    /// AC10/AC11, #97/#117).
    ///
    /// Only reached from the `.result` branch above: a cancelled, failed or
    /// unreadable run has nothing worth keeping, and an empty row between two
    /// real recommendations would be noise in the history.
    ///
    /// A failing write is logged, not surfaced: the recommendation is on screen
    /// and readable, and an error banner over it would be about the next
    /// launch, not about anything the user can act on now.
    private func persist(_ text: String) async {
        let timestamp = now()
        generatedAt = timestamp
        refreshResultAge()
        // Both are set by the time a run reaches `.result`: the context is
        // written when the window resolves, well before the first token.
        guard let resultStore, let context else { return }
        do {
            // The id is kept, so deleting this row from the history clears it
            // off this screen too, rather than whatever is newest by then (#117).
            currentResultID = try await resultStore.save(
                text: text,
                generatedAt: timestamp,
                context: context
            )
            // This run's own recommendation is now the newest, so anything that
            // was there before it is history.
            hasHistory = try await resultStore.recent(limit: 2).count > 1
        } catch {
            logger.error("Analysis not persisted: \(error, privacy: .public)")
        }
    }

    /// Ends a run: the slow hint goes, and the lock label is re-read from
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
        await refreshLock()
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

    // MARK: - Rate limit

    /// Recomputes `lockMessage` from the stored timestamp and returns the
    /// instant the lock lifts, or `nil` while a run is allowed.
    ///
    /// Callers that need the decision as well as the label take it from here
    /// rather than asking the store again: one reading of the clock and one of
    /// the store, so message and decision can never describe different
    /// instants.
    @discardableResult
    func refreshLock() async -> Date? {
        let reference = now()
        let availableAt = await rateLimit.activeLock(now: reference)
        let wasResting = lockMessage == nil
        lockMessage = RateLimitFormatter.message(until: availableAt, now: reference)
        // The lock starts mid-call, which is almost always while the ticker is
        // resting — and a resting sleep is a minute long. Without this the
        // countdown would stand still for most of the 60s it is counting down,
        // which is exactly the second-by-second stretch the fast rate exists
        // for. Cutting the sleep short here puts the loop back on `tickInterval`
        // on its next pass.
        if wasResting, lockMessage != nil {
            tickerSleep?.cancel()
        }
        // Both labels age at the same rate and are driven by the same ticker,
        // so they are refreshed together against one reading of the clock.
        refreshResultAge(now: reference)
        // A lock message on screen outlives its reason otherwise: once the
        // lock lifts, the explanation is wrong and the button is back.
        if availableAt == nil, case .error(.lockActive) = state {
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

    /// Keeps the label counting down while the screen is on display — the
    /// analysis view's `.task`.
    ///
    /// Runs until cancelled rather than until the lock lifts: the label has to
    /// appear the moment a run finishes, not only the next time the screen is
    /// opened.
    ///
    /// Two rates, because there are two things being refreshed. While the lock
    /// runs, the label is a second-by-second countdown over a 60s window. Once
    /// it lifts, only the recommendation's age is still changing, and that is
    /// worth a wake-up a minute rather than one a second.
    func trackLock() async {
        while !Task.isCancelled {
            let availableAt = await refreshLock()
            await tick(after: availableAt == nil ? restingTickInterval : tickInterval)
        }
    }

    /// Waits out one tick — or less, when `refreshLock()` sees a lock start
    /// and cancels the sleep.
    ///
    /// Its own task rather than a bare `Task.sleep`, because that is what makes
    /// the sleep interruptible from outside the loop. The cancellation handler
    /// passes the view's own cancellation through, so closing the screen still
    /// ends the wait immediately rather than a minute later.
    private func tick(after interval: TimeInterval) async {
        let sleeper = Task {
            // Discarded on purpose, and `_ =` rather than `try?` as the
            // closure's result: a cancelled sleep ends the wait exactly like
            // an elapsed one, and the optional would make this a
            // `Task<Void?, Never>`.
            _ = try? await Task.sleep(for: .seconds(interval))
        }
        tickerSleep = sleeper
        await withTaskCancellationHandler {
            await sleeper.value
        } onCancel: {
            sleeper.cancel()
        }
        tickerSleep = nil
    }
}
