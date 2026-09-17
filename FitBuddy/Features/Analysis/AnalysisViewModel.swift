import Foundation
import OSLog

/// Drives the on-demand AI analysis: builds the prompt from the local cache,
/// waits for the complete answer of whichever provider takes the call,
/// and validates a structured one against the same reads (US-3, #31/#79/#117,
/// US-14 #178).
///
/// Several things are published separately because they answer different
/// questions. `state` says what the screen shows right now, `attribution` says
/// who is answering it and who was asked before them, `resultAge` says how old
/// the recommendation on screen is, and `isTakingLong` says whether this run
/// has passed the 30s mark without an answer — the moment US-3 AC1 wants the
/// cancel button to appear.
///
/// There is no cooldown between two runs: the 60s lock of #117 is gone. A run
/// in flight still blocks a second one, so a double tap cannot buy two
/// analyses, and the hard limit on spending is the spending limit in the
/// user's own provider account (BYO key, ADR-004).
///
/// The answer is taken in one step (#178): a report is JSON, and half of it is
/// neither a report nor readable prose. The transport still streams underneath,
/// which is what keeps timeouts, cancel and the fallback chain working.
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
    /// How long a run may go without an answer before the screen offers to
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
    /// Whether the running call has passed `slowThreshold` without answering.
    /// Cleared as soon as the answer arrives, and on every state change out of
    /// the running state.
    @Published private(set) var isTakingLong = false
    /// What the analysis on screen rests on: how many sessions, over which
    /// period, from which sources (US-6, #36). `nil` until a run has resolved
    /// its window — before that there is no data basis to describe, and a
    /// guessed one would be worse than none.
    @Published private(set) var context: AnalysisContext?
    /// When the recommendation on screen was produced. Set by a finished run
    /// and by `restore()`; `nil` whenever no recommendation is showing (#97).
    @Published private(set) var generatedAt: Date?
    /// `generatedAt` as the screen prints it — `"2 h ago"`. Refreshed by
    /// `trackResultAge()`, so a screen left open does not keep claiming "just
    /// now".
    @Published private(set) var resultAge: String?
    /// Whether more than one analysis is stored, and the history is therefore
    /// worth opening (US-3 AC11, #117). With a single one the screen already
    /// shows it, and a link to a list of exactly that would be a detour.
    @Published private(set) var hasHistory = false

    /// Whether tapping "Analyse" can start a run right now: whenever no run is
    /// in flight.
    var canStartAnalysis: Bool {
        !state.isRunning
    }

    /// The run currently in flight, held so `cancel()` can stop it.
    private var runTask: Task<Void, Never>?
    /// Counts runs, so a superseded one cannot clean up after the run that
    /// replaced it.
    private var runID: UInt64 = 0
    /// Fires once `slowThreshold` has passed without an answer.
    private var slowTask: Task<Void, Never>?
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
    private let detailCache: (any WorkoutDetailReading)?
    private let inference: AnalysisStreaming
    private let resultStore: (any AnalysisResultStoring)?
    private let trainingProfile: TrainingProfileStore
    private let calendar: Calendar
    private let now: () -> Date
    private let slowThreshold: TimeInterval
    private let tickInterval: TimeInterval

    private let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "Analysis")

    /// - Parameters:
    ///   - cache: Read access to the cached window (`WorkoutStore` in the app).
    ///   - exerciseCache: Per-exercise read access for the prompt's Exercises
    ///     section (#173) — `WorkoutStore` in the app, like `cache`. `nil` —
    ///     the default — builds the prompt without exercise data, which is
    ///     what SwiftUI previews get: the prompt then says there is none, and
    ///     the system prompt forbids naming a weight it was not given. It is
    ///     also what a report is validated against (#175), so without it a
    ///     report is shown as its prose summary rather than as cards nothing
    ///     has checked.
    ///   - detailCache: Full workouts of the last seven days, for the mean RPE
    ///     of the recovery figures (#175) — `WorkoutStore` in the app. `nil` —
    ///     the default — validates without RPE.
    ///   - inference: The streaming call (`InferenceService` in the app).
    ///   - resultStore: Where a finished recommendation is persisted, so it
    ///     survives an app restart (US-3 AC10). `nil` — the default — turns
    ///     persistence off, which is what SwiftUI previews need: they have no
    ///     `ModelContainer` to build a store over.
    ///   - trainingProfile: Where the user's goal and experience live
    ///     (US-13). Read at the start of every run, not once at init: the
    ///     Settings screen changes it while this view model lives on (#191).
    ///   - now: Injectable clock, so windows and the result age are testable.
    ///   - slowThreshold: Injectable, so tests do not wait 30 real seconds.
    ///   - tickInterval: How often `trackResultAge()` re-renders the
    ///     recommendation's age. A minute: the label counts in minutes and
    ///     hours, so a faster beat would only wake the app for nothing.
    init(
        cache: WorkoutSummaryReading,
        exerciseCache: (any ExerciseSummaryReading & ExerciseProgressionReading)? = nil,
        detailCache: (any WorkoutDetailReading)? = nil,
        inference: AnalysisStreaming,
        resultStore: (any AnalysisResultStoring)? = nil,
        trainingProfile: TrainingProfileStore = TrainingProfileStore(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        slowThreshold: TimeInterval = AnalysisViewModel.defaultSlowThreshold,
        tickInterval: TimeInterval = 60
    ) {
        self.cache = cache
        self.exerciseCache = exerciseCache
        self.detailCache = detailCache
        self.inference = inference
        self.resultStore = resultStore
        self.trainingProfile = trainingProfile
        self.calendar = calendar
        self.now = now
        self.slowThreshold = slowThreshold
        self.tickInterval = tickInterval
    }

    // MARK: - Run

    /// Runs one analysis: cache read → prompt → complete answer → validation →
    /// result.
    ///
    /// Never throws. Every failure lands in `state`, so the screen always has
    /// something to show and the button always comes back (#31 AC1). A second
    /// call while one is running is ignored rather than queued — the user
    /// tapping twice must not buy two analyses. Once a run has ended, the next
    /// one may start straight away: there is no cooldown.
    func start() async {
        guard !state.isRunning else { return }
        // Claim the slot before the first await: an await releases the main
        // actor, so two taps landing in that window would otherwise both pass
        // the guard above and start a run each.
        state = .running
        // The providers of the previous run have nothing to do with this one.
        attribution = nil
        // The run the user asked for is under way, so a failure of it has to
        // be able to bring the stored recommendation back (#97).
        didDismissStoredResult = false

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
    /// Returns to `.idle`: an answer that has not arrived in full is not a
    /// recommendation, and nothing of it has been shown. The button comes back
    /// right away.
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
    /// leaving the intro screen while the recommendation is still on disk
    /// (#97).
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

        // The cards the user saw, when the row stored them (#176); prose for
        // every other row, including those written before V3.
        state = .result(stored.report.map(AnalysisOutcome.report) ?? .prose(stored.text))
        // The provider that wrote it, when the row recorded one (#176) — so
        // the badge reads "AI · Gemini" after a restart too. No fallback chain
        // is stored, so a restored result never shows the switch notice.
        attribution = stored.provider.map(AnalysisAttribution.init(first:))
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
        // `state` is already `.running` — `start()` claimed the slot there.
        startSlowTimer()

        guard let built = await buildPrompt() else { return finish(id) }

        // Collected, never shown while the run is in flight: the answer only
        // means something once the stream has ended, and a provider that gives
        // way before then takes its answer with it (#178).
        var prose = ""
        var report: AnalysisReport?
        do {
            let stream = try await inference.streamAnalysis(
                systemPrompt: built.prompt.system,
                userPrompt: built.prompt.user
            )
            for try await event in stream {
                try Task.checkCancellation()
                switch event {
                case .attempting(let provider):
                    // A provider is taking over. Whatever arrived before came
                    // from one that has since failed, and keeping it would
                    // present one model's answer under another's name.
                    prose = ""
                    report = nil
                    if attribution != nil {
                        attribution?.append(provider)
                        // The slow hint keeps counting from the tap: the user
                        // has been looking at the same spinner all along, and a
                        // handover must not take away a cancel button they may
                        // be about to press. Only when a discarded answer had
                        // already stopped the timer does it start again —
                        // otherwise the cancel button of US-3 AC1 would never
                        // come back while the new provider hangs. That branch
                        // is only reachable with a test double: `InferenceService`
                        // ends the run right after a provider's answer, so no
                        // handover ever follows one.
                        if slowTask == nil {
                            startSlowTimer()
                        }
                    } else {
                        attribution = AnalysisAttribution(first: provider)
                    }
                case .text(let text):
                    // The answer is in: the slow hint has served its purpose.
                    stopSlowTimer()
                    prose = text
                    report = nil
                case .report(let received):
                    stopSlowTimer()
                    report = received
                    prose = ""
                }
            }
            guard !Task.isCancelled else { return finish(id) }

            let outcome: AnalysisOutcome
            if let report {
                outcome = self.outcome(for: report, reads: built.reads)
            } else if !prose.isEmpty {
                outcome = .prose(prose)
            } else {
                // A stream that ends without an answer is not an empty
                // recommendation — it is a response this version could not
                // read.
                state = .error(.unreadableResponse(attribution?.provider))
                return finish(id)
            }
            // Before `.result`, not after: while the write runs the state stays
            // `.running`, so "New analysis" cannot start a second run before
            // this one has stored its answer.
            await persist(outcome)
            // A `cancel()` during the await above already published a resting
            // state; it wins over the run it stopped.
            guard !Task.isCancelled else { return finish(id) }
            // The whole answer in one step (#178).
            state = .result(outcome)
        } catch {
            // A cancelled run already published `.idle` in `cancel()`; the
            // error here is only the echo of that, and must not overwrite it.
            guard !Task.isCancelled, !error.isCancellation else { return finish(id) }
            // The provider named is the last one the chain tried — the one whose
            // failure the user is actually looking at.
            state = .error(AnalysisFailure(analysisError: error, provider: attribution?.provider))
        }
        finish(id)
    }

    /// What a report becomes on screen: validated against the reads its prompt
    /// was built from (US-14 AC3/AC4, #175).
    ///
    /// Synchronous on purpose: every read it needs was made with the prompt.
    ///
    /// Without an exercise cache — the previews' case — the prompt carried no
    /// exercise data, so every progression card would be downgraded for lack
    /// of data rather than for being wrong. The report is then shown as its
    /// summary, which is what the model wrote for exactly that purpose, and
    /// never as cards nothing has checked.
    private func outcome(for report: AnalysisReport, reads: AnalysisRunReads) -> AnalysisOutcome {
        guard exerciseCache != nil else { return .prose(report.summary) }
        let evidence = AnalysisReportEvidence(
            summaries: reads.summaries,
            exercises: reads.exercises,
            progressions: reads.progressions,
            // Unavailable details leave the recovery card without RPE, which
            // `RecoveryMetrics` already shows as "none logged" (#175).
            details: reads.details ?? [],
            window: reads.window,
            now: reads.now,
            calendar: calendar
        )
        return .report(AnalysisReportValidator.validate(report, against: evidence))
    }

    /// Reads the window and builds the prompt, or publishes the reason it
    /// could not. `nil` means the run is over.
    ///
    /// Returns the reads alongside the prompt, so a report can be validated
    /// against exactly what the model was shown (#178).
    private func buildPrompt() async -> (prompt: AnalysisPrompt, reads: AnalysisRunReads)? {
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
            let details = await readRecentDetails(in: summaries, now: reference)
            guard !Task.isCancelled else { return nil }

            // Read here, per run: what the user changed in Settings a minute
            // ago has to be what this analysis sees (US-13 AC3/AC4).
            let profile = await trainingProfile.profile

            // Counted over the resolved window, not over everything the read
            // returned: the cache was read wide enough for the widest rung and
            // its comparison window, and reporting those sessions as the data
            // basis would overstate it by a factor of six.
            context = AnalysisContext(
                sessionCount: summaries.filter { $0.startTime >= start }.count,
                window: window,
                profile: profile
            )
            let reads = AnalysisRunReads(
                summaries: summaries,
                exercises: exercises.summaries,
                progressions: exercises.progressions,
                details: details,
                window: window,
                now: reference
            )
            let prompt = AnalysisPromptBuilder.make(
                summaries: reads.summaries,
                exercises: reads.exercises,
                progressions: reads.progressions,
                window: reads.window,
                now: reads.now,
                calendar: calendar,
                profile: profile
            )
            return (prompt, reads)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return nil }
            state = .error(.cacheUnavailable)
            return nil
        }
    }

    /// The full workouts of the last seven days, for the mean RPE of the
    /// recovery figures (#175), or `nil` when they are unavailable.
    ///
    /// Read with the prompt's other reads, so a report is validated against one
    /// snapshot of the cache (#178). Unlike those reads, a failure here does
    /// not fail the run: the RPE is the one recovery figure the card can do
    /// without. It is logged, and the details count as unavailable as a whole —
    /// as does a session a sync has removed since the summaries were read.
    /// A mean over the part of the week that happened to be readable would
    /// read as the week's.
    private func readRecentDetails(
        in summaries: [WorkoutSummary],
        now reference: Date
    ) async -> [WorkoutDetail]? {
        guard let detailCache else { return nil }
        let sessions = RecoveryMetrics.lastSevenDaysSessions(in: summaries, now: reference, calendar: calendar)
        var details: [WorkoutDetail] = []
        do {
            for session in sessions {
                guard !Task.isCancelled else { return nil }
                guard let detail = try await detailCache.workoutDetail(id: session.id) else {
                    logger.notice("Workout detail for the recovery figures missing; validating without RPE")
                    return nil
                }
                details.append(detail)
            }
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return nil }
            logger.error("Workout details for the recovery figures not readable: \(error, privacy: .public)")
            return nil
        }
        return details
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
    private func persist(_ outcome: AnalysisOutcome) async {
        let timestamp = now()
        generatedAt = timestamp
        refreshResultAge()
        // Both are set by the time a run reaches `.result`: the context is
        // written when the window resolves, well before the answer.
        guard let resultStore, let context else { return }
        do {
            // The id is kept, so deleting this row from the history clears it
            // off this screen too, rather than whatever is newest by then (#117).
            // The validated report is stored as shown, so the history brings
            // back the same cards rather than re-validating against a cache
            // that has moved on; its summary is the row's prose fallback. The
            // provider is the one that answered, so the history badge can name
            // it (#176).
            currentResultID = try await resultStore.save(
                text: outcome.text,
                report: outcome.report,
                provider: attribution?.provider,
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

    /// Ends a run: the slow hint goes, and the task handle is released.
    private func finish(_ id: UInt64) {
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
            // Only while the run is still in flight: a finished or cancelled
            // run has nothing left to cancel.
            guard case .running = self.state else { return }
            self.isTakingLong = true
        }
    }

    private func stopSlowTimer() {
        // Called for every answer event: without this, each one would publish
        // an `isTakingLong` change nothing is listening for.
        guard slowTask != nil || isTakingLong else { return }
        slowTask?.cancel()
        slowTask = nil
        isTakingLong = false
    }

    // MARK: - Result age

    /// Re-renders `resultAge` from `generatedAt`.
    ///
    /// Reuses `SyncTimeFormatter`, which the sync banner already uses: the two
    /// timestamps say the same kind of thing, and a second formatter would
    /// drift from it.
    func refreshResultAge() {
        guard let generatedAt else {
            resultAge = nil
            return
        }
        resultAge = SyncTimeFormatter.relative(since: generatedAt, now: now())
    }

    /// Takes the recommendation's timestamp off the screen. Does not touch the
    /// stored one — see `start()`.
    private func clearResultAge() {
        generatedAt = nil
        resultAge = nil
    }

    /// Keeps the recommendation's age current while the screen is on display —
    /// the analysis view's `.task`. Runs until cancelled.
    func trackResultAge() async {
        while !Task.isCancelled {
            refreshResultAge()
            do {
                try await Task.sleep(for: .seconds(tickInterval))
            } catch {
                return
            }
        }
    }
}
