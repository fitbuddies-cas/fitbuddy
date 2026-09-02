import SwiftUI

/// One logged set inside an exercise card: set number on the left, the values
/// Hevy actually recorded on the right (#98).
///
/// Only logged values are rendered. A bodyweight set shows its reps and
/// nothing else, a treadmill set its distance and time — the row never fills a
/// missing metric with a zero.
struct SetDetailRow: View {
    let set: SetDetail
    /// The set's position among the *counted* sets, 1-based — `nil` for a set
    /// that is outside the volume and therefore outside the numbering. Taken
    /// from the list rather than from `set.index`, whose numbering Hevy shares
    /// with the warm-ups.
    let number: Int?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            marker
            Text(metrics)
                .font(.subheadline)
                .fbTabularNumbers()
                .foregroundStyle(Color.fbInk)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let rpe = SetMetricFormatter.rpe(set.rpe) {
                Text(rpe)
                    .font(.caption)
                    .fbTabularNumbers()
                    .foregroundStyle(Color.fbMuted)
            }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// The set number, or a mark for a set that carries none.
    ///
    /// Both branches follow `number`, which the card derives from
    /// `SetType.countsTowardsVolume` — the same rule that decided the volume
    /// printed above. A warm-up gets "W"; anything else outside the volume
    /// (`.unknown`, i.e. a missing type or one a later Hevy introduces) gets a
    /// dash, because the app cannot say more about it than that it did not
    /// count.
    private var marker: some View {
        Text(markerText)
            .font(.caption.weight(.semibold))
            .fbTabularNumbers()
            .foregroundStyle(number == nil ? Color.fbWarn : Color.fbMuted)
            .frame(width: 22, alignment: .leading)
    }

    private var markerText: String {
        guard let number else { return set.type == .warmup ? "W" : "–" }
        return "\(number)"
    }

    /// The logged values, in the order they are read: load, then work.
    ///
    /// Empty only for a set with no metric at all — Hevy allows it, and an
    /// empty row is still the truthful rendering of an empty set.
    private var metrics: String {
        [
            SetMetricFormatter.weight(set.weightKg),
            SetMetricFormatter.reps(set.reps),
            SetMetricFormatter.distance(set.distanceMeters),
            SetMetricFormatter.duration(set.durationSeconds),
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private var accessibilityLabel: String {
        [position, metrics.isEmpty ? nil : metrics, SetMetricFormatter.rpe(set.rpe)]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    /// Spoken counterpart of `markerText` — "–" would be read as a hyphen.
    private var position: String {
        guard let number else {
            return set.type == .warmup ? "Warm-up set" : "Set, not counted"
        }
        return "Set \(number)"
    }
}

#Preview {
    VStack(spacing: 0) {
        SetDetailRow(
            set: SetDetail(
                index: 0,
                type: .warmup,
                weightKg: 60,
                reps: 10,
                distanceMeters: nil,
                durationSeconds: nil,
                rpe: nil
            ),
            number: nil
        )
        SetDetailRow(
            set: SetDetail(
                index: 1,
                type: .normal,
                weightKg: 102.5,
                reps: 8,
                distanceMeters: nil,
                durationSeconds: nil,
                rpe: 9.5
            ),
            number: 1
        )
        SetDetailRow(
            set: SetDetail(
                index: 2,
                type: .normal,
                weightKg: nil,
                reps: 12,
                distanceMeters: nil,
                durationSeconds: nil,
                rpe: nil
            ),
            number: 2
        )
        SetDetailRow(
            set: SetDetail(
                index: 3,
                type: .normal,
                weightKg: nil,
                reps: nil,
                distanceMeters: 5_000,
                durationSeconds: 1_512,
                rpe: nil
            ),
            number: 3
        )
        // A type this version does not know — logged, shown, but outside the
        // volume and therefore outside the numbering.
        SetDetailRow(
            set: SetDetail(
                index: 4,
                type: .unknown,
                weightKg: 40,
                reps: 15,
                distanceMeters: nil,
                durationSeconds: nil,
                rpe: nil
            ),
            number: nil
        )
    }
    .padding(16)
    .background(Color.fbCard)
}
