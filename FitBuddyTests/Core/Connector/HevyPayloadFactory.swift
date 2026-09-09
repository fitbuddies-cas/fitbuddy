import Foundation

/// Builds `GET /v1/workouts` payloads in Hevy's wire format, so tests exercise
/// the real decoding path instead of hand-rolled structs.
enum HevyPayloadFactory {
    /// One workout with a single exercise and two sets.
    static func workout(
        id: String,
        start: Date,
        title: String = "Morning Workout",
        exerciseTitle: String = "Bench Press (Barbell)"
    ) -> [String: Any] {
        [
            "id": id,
            "title": title,
            "description": "Felt strong",
            "start_time": iso(start),
            "end_time": iso(start.addingTimeInterval(3600)),
            "updated_at": iso(start.addingTimeInterval(3600)),
            "created_at": iso(start),
            "exercises": [
                [
                    "index": 0,
                    "title": exerciseTitle,
                    "notes": "Paid attention to form",
                    "exercise_template_id": "05293BCA",
                    "supersets_id": 1,
                    "sets": [
                        [
                            "index": 0,
                            "type": "warmup",
                            "weight_kg": 60,
                            "reps": 10,
                            "distance_meters": NSNull(),
                            "duration_seconds": NSNull(),
                            "rpe": NSNull(),
                        ],
                        [
                            "index": 1,
                            "type": "normal",
                            "weight_kg": 100,
                            "reps": 8,
                            "distance_meters": NSNull(),
                            "duration_seconds": NSNull(),
                            "rpe": 9.5,
                        ],
                    ],
                ],
            ],
        ]
    }

    /// A page envelope around `workouts`.
    static func page(page: Int, pageCount: Int, workouts: [[String: Any]]) -> Data {
        let payload: [String: Any] = [
            "page": page,
            "page_count": pageCount,
            "workouts": workouts,
        ]
        // Test fixture: a payload this file builds itself cannot fail to encode.
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
