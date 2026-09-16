import SwiftUI

/// Every session of one movement in the window, newest first, each openable
/// to its sets (#163).
///
/// Collapsed by default, and newest first — the opposite order of the chart
/// above it on purpose: a curve is read left to right because that is how time
/// runs, while a list of sessions is read from the top because the last one is
/// the one being compared against. Opening every row by default would bury the
/// chart under three months of sets.
///
/// The estimate on a collapsed row is what ties the list to the curve: the
/// same number, for the same day. A session Epley cannot project from — a
/// rowing machine, a plank — falls back to what it did log, distance and time
/// before reps before a bare set count, so the row still says something about
/// the training rather than about the table.
struct ExerciseHistoryCard: View {
    let sessions: [ExerciseHistoryEntry]

    /// Which sessions are open, by workout id. A set rather than one selected
    /// id: a user comparing two sessions wants both on screen, and the
    /// accordion that closes one to open the next makes that impossible.
    @State private var expanded: Set<String> = []

    var body: some View {
        FBCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header
                ForEach(Array(newestFirst.enumerated()), id: \.element.id) { index, session in
                    if index > 0 {
                        Divider().overlay(Color.fbDivider)
                    }
                    row(for: session)
                }
            }
        }
    }

    private var newestFirst: [ExerciseHistoryEntry] {
        sessions.sorted { $0.sessionStart > $1.sessionStart }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("History".uppercased())
                .font(.fbLabel)
                .tracking(0.6)
                .foregroundStyle(Color.fbMuted)
            Spacer()
            Text(CountFormatter.labelled(sessions.count, singular: "session"))
                .font(.caption2)
                .foregroundStyle(Color.fbMuted)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
        // On the header, not on the card: an identifier set on a container
        // propagates down and overwrites the rows' own, which left the tests
        // unable to address a single session.
        .accessibilityIdentifier(AccessibilityID.Progression.history)
    }

    @ViewBuilder
    private func row(for session: ExerciseHistoryEntry) -> some View {
        let isExpanded = expanded.contains(session.id)

        VStack(alignment: .leading, spacing: 0) {
            Button {
                // Animated from here rather than with `.animation(value:)` on
                // the card: only the tap should animate, not a reload that
                // swaps the whole list underneath.
                withAnimation(.snappy(duration: 0.2)) { toggle(session) }
            } label: {
                summary(for: session, isExpanded: isExpanded)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityID.Progression.historyRow)
            .accessibilityLabel(accessibilityLabel(for: session))
            .accessibilityHint(isExpanded ? "Hides the sets" : "Shows the sets")

            if isExpanded {
                sets(of: session)
            }
        }
    }

    private func summary(for session: ExerciseHistoryEntry, isExpanded: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.fbMuted)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 10)
            Text(session.sessionStart, format: .dateTime.day().month(.abbreviated))
                .font(.subheadline)
                .foregroundStyle(Color.fbInk)
            Spacer(minLength: 8)
            Text(trailingValue(for: session))
                .font(.subheadline.weight(.semibold))
                .fbTabularNumbers()
                .foregroundStyle(session.estimatedOneRepMaxKg == nil ? Color.fbMuted : Color.fbInk)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func sets(of session: ExerciseHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(session.sets.numbered, id: \.set.id) { entry in
                SetDetailRow(set: entry.set, number: entry.number)
                    .accessibilityIdentifier(AccessibilityID.Progression.historySet)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    /// The estimate, or — where there is none — what the session did log.
    ///
    /// "1 set" would be true and useless: for a rowing machine the interesting
    /// number is the distance, for a plank the time, for a bodyweight movement
    /// the reps. The fallbacks run in that order and stop at the first thing
    /// the session actually recorded.
    private func trailingValue(for session: ExerciseHistoryEntry) -> String {
        if let estimate = session.estimatedOneRepMaxKg {
            return "\(OneRepMaxFormatter.kilograms(estimate)) kg"
        }
        if let distance = SetMetricFormatter.distance(session.totalDistanceMeters) {
            guard let duration = SetMetricFormatter.duration(session.totalDurationSeconds) else {
                return distance
            }
            return "\(distance) · \(duration)"
        }
        if let duration = SetMetricFormatter.duration(session.totalDurationSeconds) {
            return duration
        }
        if let reps = SetMetricFormatter.reps(session.totalReps) {
            return reps
        }
        return CountFormatter.labelled(session.sets.count, singular: "set")
    }

    private func accessibilityLabel(for session: ExerciseHistoryEntry) -> String {
        let date = session.sessionStart.formatted(.dateTime.day().month(.wide))
        guard let estimate = session.estimatedOneRepMaxKg else {
            return "\(date), \(trailingValue(for: session))"
        }
        return "\(date), estimated one-rep max \(OneRepMaxFormatter.kilograms(estimate)) kilograms"
    }

    private func toggle(_ session: ExerciseHistoryEntry) {
        if expanded.contains(session.id) {
            expanded.remove(session.id)
        } else {
            expanded.insert(session.id)
        }
    }
}

#if DEBUG
#Preview("History") {
    ScrollView {
        ExerciseHistoryCard(sessions: PreviewProgressionCache.sessions([96, 101, 104, 107.5]))
            .padding(16)
    }
    .background(Color.fbBackground)
}

#Preview("History without a curve") {
    ScrollView {
        ExerciseHistoryCard(sessions: PreviewProgressionCache.cardioSessions(4))
            .padding(16)
    }
    .background(Color.fbBackground)
}
#endif
