import SwiftUI

/// The sync strip above the dashboard: the per-source status rows (US-2 AC2,
/// US-8 AC1) and, when the last sync failed, the cached-data banner (#28).
///
/// All of it lives in one view because it is one statement to the user: how old
/// the data is, and whether that is going to change on its own. The banner
/// disappears the moment a sync succeeds; the source rows never do.
struct SyncStatusView: View {
    let status: SyncStatus
    /// The sources the strip reports on — one per row (#40). v0 hands in Hevy
    /// alone; `DataSourceStatusView` loops either way.
    let sources: [DataSourceStatus]
    /// Overrides the clock, so the rendered age is deterministic in tests.
    /// `nil` in the app, where the timeline below supplies the current time.
    var now: Date?
    /// Syncs again. Takes no source: v0 has one sync path that refills the
    /// whole cache, so both the banner's button and a stale row's mean the
    /// same thing.
    let onRetry: () -> Void
    /// The re-auth link US-5 AC2 asks for: a source whose token can only be
    /// renewed by the user. Defaults to nothing, for callers that only have
    /// one source.
    var onRenew: (ConnectorSource) -> Void = { _ in }

    /// The sync the banner is about. The banner reports the attempt that just
    /// failed, and in v0 exactly one source is ever synced — see
    /// `WorkoutSyncService`.
    ///
    /// - Note: **Does not scale to a second source (#35).** With two sources
    ///   this would report the first one's timestamp whichever of them
    ///   actually failed. It falls away once `SyncStatus` is tracked per
    ///   source rather than per dashboard; until then, unreachable — the
    ///   registry has one real connector.
    private var lastSync: Date? { sources.first?.lastSync }

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
        switch status {
        case .failed(let failure):
            // The banner carries the timestamp in its own subtitle, so the
            // source rows underneath would print it twice — and a stale badge
            // next to a failure the user is already being told about only
            // splits their attention. The banner is the whole report while it
            // is up (US-2 AC2 is met either way).
            //
            // Does not scale to a second source (#35): this hides *every*
            // source row, so a Hevy failure would also swallow a stale Strava
            // row that has nothing to do with it. Same fix as `lastSync`
            // above — a per-source `SyncStatus`.
            banner(failure, now: now)
        case .degraded(let failures):
            // A partial sync (#143, #144): one banner per source that is
            // missing from the fresh data, in a fixed order so they do not
            // reshuffle between syncs, and the ordinary status row for every
            // source that did sync — each source gets exactly one statement.
            VStack(spacing: 8) {
                ForEach(ConnectorSource.allCases.filter { failures[$0] != nil }) { source in
                    if let failure = failures[source] {
                        sourceBanner(source, failure, now: now)
                    }
                }
                DataSourceStatusView(
                    sources: sources.filter { failures[$0.source] == nil },
                    now: now,
                    onRetry: { _ in onRetry() }
                )
            }
        case .idle, .syncing:
            DataSourceStatusView(sources: sources, now: now, onRetry: { _ in onRetry() })
        }
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

    /// A partial sync's banner for one source (#144). Two shapes: a token
    /// only the user can renew gets the renewal prompt and a link into the
    /// re-auth flow (US-5 AC2); anything else names the source and offers the
    /// same retry as the full-failure banner.
    private func sourceBanner(_ source: ConnectorSource, _ failure: SyncFailure, now: Date) -> some View {
        let needsRenewal = failure == .connectionExpired
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: failure.symbolName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.fbWarn)

            VStack(alignment: .leading, spacing: 2) {
                Text(needsRenewal ? source.renewalPrompt : "\(source.displayName) not synced")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.fbInk)
                Text(bannerDetail(failure, now: now))
                    .font(.caption)
                    .foregroundStyle(Color.fbInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if needsRenewal {
                Button("Reconnect") { onRenew(source) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.fbWarn)
                    .accessibilityIdentifier(AccessibilityID.Dashboard.renewButton)
            } else {
                Button("Retry", action: onRetry)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.fbWarn)
            }
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(needsRenewal ? AccessibilityID.Dashboard.renewalBanner : AccessibilityID.Dashboard.sourceBanner)
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
            sources: [DataSourceStatus(source: .hevy, lastSync: Date().addingTimeInterval(-8_040))],
            onRetry: {}
        )
        SyncStatusView(
            status: .failed(.keychainUnavailable),
            sources: [DataSourceStatus(source: .hevy, lastSync: nil)],
            onRetry: {}
        )
        SyncStatusView(
            status: .failed(.rateLimited(retryAfter: 45)),
            sources: [DataSourceStatus(source: .hevy, lastSync: Date().addingTimeInterval(-300))],
            onRetry: {}
        )
        SyncStatusView(
            status: .syncing,
            sources: [DataSourceStatus(source: .hevy, lastSync: nil, isSyncing: true)],
            onRetry: {}
        )
        SyncStatusView(
            status: .idle,
            sources: [DataSourceStatus(source: .hevy, lastSync: Date().addingTimeInterval(-120))],
            onRetry: {}
        )
        // Nothing failed, nothing running — and the data is three days old
        // (US-8 AC1).
        SyncStatusView(
            status: .idle,
            sources: [DataSourceStatus(source: .hevy, lastSync: Date().addingTimeInterval(-3 * 86_400))],
            onRetry: {}
        )
        SyncStatusView(
            status: .degraded(failures: [.strava: .connectionExpired]),
            sources: [
                DataSourceStatus(source: .hevy, lastSync: Date().addingTimeInterval(-60)),
                DataSourceStatus(source: .strava, lastSync: Date().addingTimeInterval(-60)),
            ],
            onRetry: {}
        )
    }
    .padding(16)
    .background(Color.fbBackground)
}
#endif
