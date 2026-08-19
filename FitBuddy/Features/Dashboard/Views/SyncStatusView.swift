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
    /// Injectable clock, so the rendered age is deterministic in tests.
    var now: Date = Date()
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if case .failed(let failure) = status {
                banner(failure)
            }
            timestampLine
        }
    }

    // MARK: - Timestamp

    /// Visible in every state, including while a sync is running and after one
    /// failed — that is the point of US-2 AC2.
    private var timestampLine: some View {
        HStack(spacing: 6) {
            Image(systemName: status == .syncing ? "arrow.triangle.2.circlepath" : "clock")
                .font(.caption)
            Text(timestampText)
                .font(.fbLabel)
                .fbTabularNumbers()
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.fbMuted)
        .accessibilityElement(children: .combine)
    }

    private var timestampText: String {
        status == .syncing
            ? "Syncing with Hevy…"
            : SyncTimeFormatter.lastSynced(lastSync, now: now)
    }

    // MARK: - Banner

    private func banner(_ failure: SyncFailure) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.fbWarn)

            VStack(alignment: .leading, spacing: 2) {
                Text(bannerTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.fbInk)
                Text(bannerDetail(failure))
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

    private func bannerDetail(_ failure: SyncFailure) -> String {
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
        SyncStatusView(status: .failed(.offline), lastSync: nil, onRetry: {})
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
