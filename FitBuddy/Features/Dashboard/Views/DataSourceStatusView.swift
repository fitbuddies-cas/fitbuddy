import SwiftUI

/// Per-source sync status on the dashboard: which provider delivered, when it
/// last did, and — once that is longer than a day ago — a stale indicator with
/// a retry button (US-8 AC1, #40).
///
/// One row per source. In v0 that is Hevy alone, which is why the strip reads
/// as a single line; the loop is what keeps this from being rewritten when
/// Strava's connector lands (#35).
///
/// Takes `now` rather than reading the clock itself: the caller drives a
/// `TimelineView`, and a second clock inside here would let the printed age and
/// the stale verdict drift apart mid-render.
struct DataSourceStatusView: View {
    let sources: [DataSourceStatus]
    let now: Date
    let onRetry: (ConnectorSource) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(sources) { source in
                row(for: source)
            }
        }
    }

    @ViewBuilder
    private func row(for source: DataSourceStatus) -> some View {
        if source.needsAttention(now: now) {
            staleRow(for: source)
        } else {
            currentRow(for: source)
        }
    }

    // MARK: - Current

    /// The quiet case — synced within the day, or syncing right now. Carries
    /// the timestamp and nothing else (US-2 AC2); there is nothing to act on.
    private func currentRow(for source: DataSourceStatus) -> some View {
        HStack(spacing: 6) {
            Image(systemName: source.isSyncing ? "arrow.triangle.2.circlepath" : "clock")
                .font(.caption)
            Text(line(for: source))
                .font(.fbLabel)
                .fbTabularNumbers()
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.fbMuted)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Stale

    /// The source has not delivered in over a day, or never did (US-8 AC1).
    ///
    /// Same warning chrome as the failed-sync banner, deliberately: to the user
    /// both mean "what you are looking at is not current, and here is the
    /// button". A muted line would let a week-old dashboard pass for a fresh
    /// one, which is the whole failure mode US-8 names.
    private func staleRow(for source: DataSourceStatus) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.fbWarn)

            VStack(alignment: .leading, spacing: 2) {
                Text(title(for: source))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.fbInk)
                Text(line(for: source))
                    .font(.caption)
                    .foregroundStyle(Color.fbInkSecondary)
                    .fbTabularNumbers()
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button("Retry") { onRetry(source.source) }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.fbWarn)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fbWarnSoft)
        .clipShape(RoundedRectangle(cornerRadius: FBRadius.control))
        .overlay(
            RoundedRectangle(cornerRadius: FBRadius.control)
                .strokeBorder(Color.fbWarn.opacity(0.25), lineWidth: 1)
        )
        // Contained rather than combined: the retry button has to stay its own
        // element for VoiceOver, which `.combine` would fold into the label.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Dashboard.staleSource(source.source.rawValue))
    }

    /// Names the source and what is wrong with it, so the headline stands on
    /// its own — "Hevy is out of date" needs no second line to be understood.
    private func title(for source: DataSourceStatus) -> String {
        source.freshness(now: now) == .never
            ? "\(source.source.displayName) has not synced yet"
            : "\(source.source.displayName) is out of date"
    }

    /// `"Hevy · Last synced 2 days ago"`. The provider name leads, because the
    /// point of the strip is which source the timestamp belongs to.
    private func line(for source: DataSourceStatus) -> String {
        source.source.displayName + " · " + source.summary(now: now)
    }
}

#if DEBUG
#Preview("Data sources") {
    VStack(spacing: 20) {
        DataSourceStatusView(
            sources: [DataSourceStatus(source: .hevy, lastSync: Date().addingTimeInterval(-840))],
            now: Date(),
            onRetry: { _ in }
        )
        DataSourceStatusView(
            sources: [DataSourceStatus(source: .hevy, lastSync: nil, isSyncing: true)],
            now: Date(),
            onRetry: { _ in }
        )
        DataSourceStatusView(
            sources: [DataSourceStatus(source: .hevy, lastSync: Date().addingTimeInterval(-3 * 86_400))],
            now: Date(),
            onRetry: { _ in }
        )
        DataSourceStatusView(
            sources: [DataSourceStatus(source: .hevy, lastSync: nil)],
            now: Date(),
            onRetry: { _ in }
        )
        // Two sources, as the strip will look once Strava's connector is real.
        DataSourceStatusView(
            sources: [
                DataSourceStatus(source: .hevy, lastSync: Date().addingTimeInterval(-300)),
                DataSourceStatus(source: .strava, lastSync: Date().addingTimeInterval(-4 * 86_400)),
            ],
            now: Date(),
            onRetry: { _ in }
        )
    }
    .padding(16)
    .background(Color.fbBackground)
}
#endif
