import Foundation

/// Drives the progression screen for one movement (US-9, #42).
///
/// Reads the cache and nothing else — like the exercise list it hangs off, and
/// for the same reason: the dashboard owns the sync, so opening this screen
/// never costs a Hevy request.
///
/// It holds the `ExerciseSummary` it was pushed with, so the title and the
/// muscle group are on screen from the first frame instead of appearing once
/// the read lands. The row the user tapped already knew them.
@MainActor
final class ExerciseProgressionViewModel: ObservableObject {
    @Published private(set) var state: ExerciseProgressionState = .loading

    /// The row this screen was opened from.
    let exercise: ExerciseSummary

    private let cache: ExerciseProgressionReading
    private let calendar: Calendar
    private let now: () -> Date

    /// - Parameters:
    ///   - cache: Read access to the cached window (`WorkoutStore` in the app).
    ///   - exercise: The tapped row — its `id` identifies the movement.
    ///   - now: Injectable clock, so the window boundary is testable.
    init(
        cache: ExerciseProgressionReading,
        exercise: ExerciseSummary,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.cache = cache
        self.exercise = exercise
        self.calendar = calendar
        self.now = now
    }

    /// Reads the movement's curve out of the window.
    ///
    /// The same 90-day window every other screen reads. US-9 says twelve
    /// weeks; the cache holds ninety days, and a second boundary six days
    /// apart would put two different answers to "in the last weeks" into one
    /// app.
    func load() async {
        let windowStart = TrainingWindow.start(endingAt: now(), calendar: calendar)
        do {
            guard let progression = try await cache.exerciseProgression(
                id: exercise.id,
                since: windowStart
            ) else {
                state = .unavailable
                return
            }
            state = progression.isPlottable ? .loaded(progression) : .insufficientData(progression)
        } catch {
            state = .failed
        }
    }

    /// The progression behind the current state, when there is one.
    var progression: ExerciseProgression? {
        switch state {
        case .loaded(let progression), .insufficientData(let progression):
            return progression
        case .loading, .unavailable, .failed:
            return nil
        }
    }

    /// Whether the plateau badge belongs on screen (AC2).
    ///
    /// Only over a plottable curve: a movement with one session has nothing to
    /// have stalled against, and the badge would read as a verdict on data
    /// that does not support one.
    var showsPlateauBadge: Bool {
        guard case .loaded(let progression) = state else { return false }
        return progression.isPlateaued
    }

    /// Sessions that produced a point — what the "not enough data yet" hint
    /// counts down from (AC3).
    var plottedSessionCount: Int {
        progression?.points.count ?? 0
    }

    /// What the window actually holds, as a sentence the hint leads with.
    ///
    /// Here rather than in the view: it is a count turned into one of three
    /// phrasings, which is a decision with a right answer — and therefore
    /// something to hold in place with a test rather than to eyeball in a
    /// preview.
    var sessionsSoFarDescription: String {
        switch plottedSessionCount {
        case 0:
            return "The last \(TrainingWindow.days) days hold no set of this exercise with both weight and reps."
        case 1:
            return "The last \(TrainingWindow.days) days hold one session with weight and reps."
        default:
            return "The last \(TrainingWindow.days) days hold \(plottedSessionCount) sessions with weight and reps."
        }
    }
}
