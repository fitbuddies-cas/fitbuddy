import SwiftUI

/// One logged set inside an exercise card: set number on the left, the values
/// Hevy actually recorded on the right (#98).
///
/// Only logged values are rendered. A bodyweight set shows its reps and
/// nothing else, a treadmill set its distance and time — the row never fills a
/// missing metric with a zero.
struct SetDetailRow: View {
    let set: SetDetail
    /// The set's position among the *displayed* sets, 1-based. Taken from the
    /// list rather than from `set.index`, whose numbering Hevy shares with the
    /// warm-ups.
    let number: Int

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

    /// The set number, or "W" for a warm-up: warm-ups are visible as such
    /// because they do not count towards the volume printed above them
    /// (`SetType.countsTowardsVolume`).
    private var marker: some View {
        Text(set.type == .warmup ? "W" : "\(number)")
            .font(.caption.weight(.semibold))
            .fbTabularNumbers()
            .foregroundStyle(set.type == .warmup ? Color.fbWarn : Color.fbMuted)
            .frame(width: 22, alignment: .leading)
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
        let position = set.type == .warmup ? "Warm-up set" : "Set \(number)"
        return [position, metrics.isEmpty ? nil : metrics, SetMetricFormatter.rpe(set.rpe)]
            .compactMap { $0 }
            .joined(separator: ", ")
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
            number: 0
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
    }
    .padding(16)
    .background(Color.fbCard)
}
