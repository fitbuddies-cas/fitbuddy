import SwiftUI

/// Connect, inspect and disconnect the Polar account (#157, US-5 AC1).
///
/// Simpler than `StravaConnectionView`: there is no application-credentials
/// screen to link to — Polar is a PKCE public client with a team-wide
/// `clientID` (ADR-11) — so the status card and the two buttons are the whole
/// screen.
struct PolarConnectionView: View {
    @StateObject private var viewModel: PolarConnectionViewModel

    /// - Parameter viewModel: Built lazily — the autoclosure is evaluated
    ///   once, when SwiftUI first creates the view's state.
    init(viewModel: @autoclosure @escaping () -> PolarConnectionViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    private var isAuthorizing: Bool { viewModel.state == .authorizing }

    private var failure: PolarConnectionFailure? {
        if case .failed(let failure) = viewModel.state { return failure }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                statusCard
                if let failure {
                    errorBanner(for: failure)
                        .padding(.top, 18)
                }
                privacyNote
                    .padding(.top, 18)
            }
            .padding(20)
        }
        .background(Color.fbBackground)
        .navigationTitle(ConnectorSource.polar.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { actions.padding(16) }
        .animation(.easeOut(duration: 0.15), value: viewModel.state)
        .task { await viewModel.bootstrap() }
    }

    // MARK: - Sections

    private var statusCard: some View {
        FBCard(padding: 18) {
            FBInfoRow(icon: statusIcon, title: statusTitle, text: statusText)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(AccessibilityID.PolarConnection.status)
        }
    }

    private var statusIcon: String {
        switch viewModel.state {
        case .unknown, .idle: return "link"
        case .authorizing: return "safari"
        case .connected: return "checkmark.circle"
        case .expired: return "exclamationmark.arrow.circlepath"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var statusTitle: String {
        switch viewModel.state {
        case .unknown: return "Checking…"
        case .idle: return "Not connected"
        case .authorizing: return "Waiting for Polar…"
        case .connected: return "Connected"
        case .expired: return "Connection expired"
        case .failed: return "Not connected"
        }
    }

    private var statusText: String {
        switch viewModel.state {
        case .unknown:
            return "Reading the stored connection."
        case .idle, .failed:
            return "Connect to pull your Polar endurance sessions into the dashboard alongside your Hevy workouts."
        case .authorizing:
            return "Sign in to Polar in the sheet and allow FitBuddy to read your training sessions."
        case .connected(let expiresAt):
            return "Your sessions sync with the dashboard. The access token renews itself; it is currently valid until \(Self.expiryFormatter.string(from: expiresAt))."
        case .expired:
            return "The token could not be renewed — Polar may have revoked it. Reconnect to keep syncing."
        }
    }

    private static let expiryFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private func errorBanner(for failure: PolarConnectionFailure) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(failure.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.fbRed)
            Text(failure.message)
                .font(.footnote)
                .foregroundStyle(Color.fbInkSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fbRedSoft)
        .clipShape(RoundedRectangle(cornerRadius: FBRadius.control))
        .overlay(
            RoundedRectangle(cornerRadius: FBRadius.control)
                .strokeBorder(Color.fbRedBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.PolarConnection.errorBanner)
    }

    private var privacyNote: some View {
        Label(
            "Tokens are stored in the Apple Keychain on this device only. FitBuddy reads your sessions and never writes to Polar.",
            systemImage: "lock"
        )
        .font(.caption)
        .foregroundStyle(Color.fbMuted)
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                Task { await viewModel.connect() }
            } label: {
                Text(connectTitle)
            }
            .buttonStyle(.fb(.primary))
            .disabled(!viewModel.canConnect)
            .accessibilityIdentifier(AccessibilityID.PolarConnection.connectButton)

            if viewModel.isConnected {
                Button {
                    Task { await viewModel.disconnect() }
                } label: {
                    Text("Disconnect")
                }
                .buttonStyle(.fb(.danger))
                .disabled(isAuthorizing)
                .accessibilityIdentifier(AccessibilityID.PolarConnection.disconnectButton)
            }
        }
    }

    private var connectTitle: String {
        switch viewModel.state {
        case .authorizing: return "Waiting for \(ConnectorSource.polar.displayName)…"
        case .connected, .expired: return "Reconnect"
        case .failed: return "Try again"
        case .unknown, .idle: return "Connect with \(ConnectorSource.polar.displayName)"
        }
    }
}
