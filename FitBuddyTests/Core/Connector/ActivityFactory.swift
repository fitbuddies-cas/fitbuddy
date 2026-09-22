import Foundation
@testable import FitBuddy

/// Builds normalized `Activity` values — what a `FitnessConnector` hands to
/// everything above it (ADR-6, #34).
///
/// The counterpart to `HevyPayloadFactory`: that one builds Hevy's wire format
/// for tests that exercise the connector's decoding, this one builds the
/// normalized shape for tests above the connector, which must not know a
/// provider exists. Both describe the same session, so an assertion can be
/// moved between them without changing its expected values.
enum ActivityFactory {
    /// One activity with a single exercise and two sets — a warm-up and a
    /// working set.
    static func activity(
        id: String,
        start: Date,
        title: String = "Morning Workout",
        exerciseTitle: String = "Bench Press (Barbell)"
    ) -> Activity {
        Activity(
            id: id,
            title: title,
            notes: "Felt strong",
            startTime: start,
            endTime: start.addingTimeInterval(3600),
            updatedAt: start.addingTimeInterval(3600),
            exercises: [
                ActivityExercise(
                    index: 0,
                    title: exerciseTitle,
                    notes: "Paid attention to form",
                    templateID: "05293BCA",
                    // A real value, not `nil`: every field of this mapping has
                    // to be able to fail a test by going missing, and the
                    // superset marker is one the detail card renders.
                    supersetID: 1,
                    sets: [
                        ActivityExerciseSet(index: 0, type: .warmup, weightKg: 60, reps: 10),
                        ActivityExerciseSet(index: 1, type: .normal, weightKg: 100, reps: 8, rpe: 9.5),
                    ]
                ),
            ]
        )
    }

    /// One endurance session as Strava or Polar hands it over (#180): a
    /// classified sport with a full cardio block and no sets worth counting.
    static func cardioActivity(
        id: String,
        start: Date,
        source: ConnectorSource = .strava,
        kind: ActivityKind = .run,
        cardio: CardioMetrics = CardioMetrics(
            averageHeartRate: 148,
            maxHeartRate: 172,
            elevationGainMeters: 412.5,
            averageSpeedMetersPerSecond: 2.78,
            energyKilojoules: 920,
            perceivedEffort: 64,
            activeCalories: 530,
            distanceMeters: 10_400,
            durationSeconds: 3742,
            trainingLoad: 143.22
        )
    ) -> Activity {
        Activity(
            id: id,
            title: "Trail Run",
            startTime: start,
            endTime: start.addingTimeInterval(3742),
            source: source,
            kind: kind,
            cardio: cardio
        )
    }
}
