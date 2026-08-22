import SwiftUI

/// The sync strip above the dashboard: the always-visible "last synced" line
/// (US-2 AC2) and, when the last sync failed, the cached-data banner (#28).
///
/// Both live in one view because they are one statement to the user: how old
/// the data is, and whether that is going to change on its own. The banner
/// disappears the moment a sync succeeds; the timestamp never does.
struct SyncStatusView: View {
    let status: SyncStatus
    let lastSync: Date?
    /// Overrides the clock, so the rendered age is deterministic in tests.
    /// `nil` in the app, where the timeline below supplies the current time.
    var now: Date?
    let onRetry: () -> Void

    var body: some View {
        // The rendered age has to keep up with the clock on its own. Nothing
        // republishes while a sync is failed — the dashboard just sits there —
        // so a view that reads `Date()` once at init would still claim "2 min
        // ago" an hour later, which is the single statement this strip exists
        // to make. A minute is the finest unit the copy shows.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(now: now ?? context.date)
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if case .failed(let failure) = status {
            // The banner carries the timestamp in its own subtitle, so the
            // separate line underneath would print it twice (US-2 AC2 is met
            // either way — the banner *is* the visible statement).
            banner(failure, now: now)
        } else {
            timestampLine(now: now)
        }
    }

    // MARK: - Timestamp

    /// Visible whenever no banner is up — including while a sync runs. That,
    /// plus the banner's own subtitle, is US-2 AC2.
    private func timestampLine(now: Date) -> some View {
        HStack(spacing: 6) {
            Image(systemName: status == .syncing ? "arrow.triangle.2.circlepath" : "clock")
                .font(.caption)
            Text(timestampText(now: now))
                .font(.fbLabel)
                .fbTabularNumbers()
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.fbMuted)
        .accessibilityElement(children: .combine)
    }

    private func timestampText(now: Date) -> String {
        status == .syncing
            ? "Syncing with Hevy…"
            : SyncTimeFormatter.lastSynced(lastSync, now: now)
    }

    // MARK: - Banner

    private func banner(_ failure: SyncFailure, now: Date) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: failure.symbolName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.fbWarn)

            VStack(alignment: .leading, spacing: 2) {
                Text(bannerTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.fbInk)
                Text(bannerDetail(failure, now: now))
                    .font(.caption)
                    .foregroundStyle(Color.fbInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button("Retry", action: onRetry)
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
    }

    /// Claiming "showing cached data" with an empty cache would be a lie — a
    /// user whose very first sync failed has nothing cached to show.
    private var bannerTitle: String {
        lastSync == nil ? "Not synced yet" : "Showing cached data"
    }

    private func bannerDetail(_ failure: SyncFailure, now: Date) -> String {
        SyncTimeFormatter.lastSynced(lastSync, now: now) + " · " + failure.summary
    }
}

#if DEBUG
#Preview("Offline") {
    VStack(spacing: 20) {
        SyncStatusView(
            status: .failed(.offline),
            lastSync: Date().addingTimeInterval(-8_040),
            onRetry: {}
        )
        SyncStatusView(status: .failed(.keychainUnavailable), lastSync: nil, onRetry: {})
        SyncStatusView(
            status: .failed(.rateLimited(retryAfter: 45)),
            lastSync: Date().addingTimeInterval(-300),
            onRetry: {}
        )
        SyncStatusView(status: .syncing, lastSync: nil, onRetry: {})
        SyncStatusView(
            status: .idle,
            lastSync: Date().addingTimeInterval(-120),
            onRetry: {}
        )
    }
    .padding(16)
    .background(Color.fbBackground)
}
#endif
