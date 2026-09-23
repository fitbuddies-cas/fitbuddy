import Foundation

/// Builds `GET /v1/workouts` payloads in Hevy's wire format, so tests exercise
/// the real decoding path instead of hand-rolled structs.
enum HevyPayloadFactory {
    /// One workout with a single exercise and two sets.
    ///
    /// - Parameter routineID: Sent as `routine_id` when given; left out of
    ///   the payload otherwise, the way a freely logged workout arrives.
    static func workout(
        id: String,
        start: Date,
        title: String = "Morning Workout",
        exerciseTitle: String = "Bench Press (Barbell)",
        routineID: String? = nil
    ) -> [String: Any] {
        var payload: [String: Any] = [
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
        if let routineID { payload["routine_id"] = routineID }
        return payload
    }

    /// One routine in the shape of `GET /v1/routines`, prescribing the same
    /// exercise as `workout(...)` — a warm-up and a working set — so its
    /// targets line up with the logged sets by position.
    ///
    /// - Parameter exercises: Overrides the prescribed exercises; each entry
    ///   is `routineExercise(...)`.
    static func routine(
        id: String,
        updatedAt: Date,
        title: String = "Push Day",
        exercises: [[String: Any]]? = nil
    ) -> [String: Any] {
        [
            "id": id,
            "title": title,
            "folder_id": NSNull(),
            "updated_at": iso(updatedAt),
            "created_at": iso(updatedAt.addingTimeInterval(-86_400)),
            "exercises": exercises ?? [
                routineExercise(templateID: "05293BCA", sets: [
                    routineSet(type: "warmup", reps: 10),
                    routineSet(type: "normal", repRange: (8, 12)),
                ]),
            ],
        ]
    }

    /// One prescribed exercise of a routine.
    static func routineExercise(
        templateID: String,
        title: String = "Bench Press (Barbell)",
        sets: [[String: Any]]
    ) -> [String: Any] {
        [
            "index": 0,
            "title": title,
            "notes": "",
            "exercise_template_id": templateID,
            "superset_id": NSNull(),
            "rest_seconds": 120,
            "sets": sets,
        ]
    }

    /// One prescribed set. `reps` and `repRange` are both optional, as on
    /// the wire, where a set carries one, the other, or neither.
    static func routineSet(
        type: String = "normal",
        weightKg: Double? = 100,
        reps: Int? = nil,
        repRange: (start: Int?, end: Int?)? = nil
    ) -> [String: Any] {
        var set: [String: Any] = [
            "index": 0,
            "type": type,
            "weight_kg": weightKg.map { $0 as Any } ?? NSNull(),
            "reps": reps.map { $0 as Any } ?? NSNull(),
            "distance_meters": NSNull(),
            "duration_seconds": NSNull(),
            "custom_metric": NSNull(),
        ]
        if let repRange {
            set["rep_range"] = [
                "start": repRange.start.map { $0 as Any } ?? NSNull(),
                "end": repRange.end.map { $0 as Any } ?? NSNull(),
            ]
        } else {
            set["rep_range"] = NSNull()
        }
        return set
    }

    /// A page envelope around `routines`.
    static func routinesPage(page: Int, pageCount: Int, routines: [[String: Any]]) -> Data {
        let payload: [String: Any] = [
            "page": page,
            "page_count": pageCount,
            "routines": routines,
        ]
        // Test fixture: a payload this file builds itself cannot fail to encode.
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
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
