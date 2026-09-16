import SwiftUI

/// Connect, inspect and disconnect the Polar account (#157, US-5 AC1).
///
/// Mirrors `StravaConnectionView` (ADR-11, BYO-app): one card states
/// where things stand — no credentials, ready to connect, connected until a
/// time, expired — and the buttons under it are the only actions there are.
/// The application credentials have their own screen, reached from here; the
/// OAuth sheet itself is presented by the system on top of this view.
struct PolarConnectionView: View {
    @StateObject private var viewModel: PolarConnectionViewModel
    private let makeCredentialsViewModel: @MainActor () -> PolarCredentialsViewModel

    /// - Parameters:
    ///   - viewModel: Built lazily — the autoclosure is evaluated once, when
    ///     SwiftUI first creates the view's state.
    ///   - makeCredentialsViewModel: Called once per push of the credentials
    ///     screen.
    init(
        viewModel: @autoclosure @escaping () -> PolarConnectionViewModel,
        makeCredentialsViewModel: @escaping @MainActor () -> PolarCredentialsViewModel
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.makeCredentialsViewModel = makeCredentialsViewModel
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
                credentialsLink
                    .padding(.top, 18)
                privacyNote
                    .padding(.top, 18)
            }
            .padding(20)
        }
        .background(Color.fbBackground)
        .navigationTitle(PolarKeyPresentation.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { actions.padding(16) }
        .animation(.easeOut(duration: 0.15), value: viewModel.state)
        .task { await viewModel.bootstrap() }
        // Coming back from the credentials screen: the pair may have just
        // been entered (or replaced), and the buttons have to reflect it.
        .onAppear { Task { await viewModel.refreshStoredState() } }
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
        case .unknown, .idle, .missingCredentials: return "link"
        case .authorizing: return "safari"
        case .connected: return "checkmark.circle"
        case .expired: return "exclamationmark.arrow.circlepath"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var statusTitle: String {
        switch viewModel.state {
        case .unknown: return "Checking…"
        case .missingCredentials: return "Not set up"
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
        case .missingCredentials:
            return "Enter the credentials of your Polar API application first. FitBuddy connects through an application that belongs to you."
        case .idle, .failed:
            return "Connect to pull your Polar endurance sessions into the dashboard alongside your Hevy workouts."
        case .authorizing:
            return "Sign in to Polar in the sheet and allow FitBuddy to read your training sessions."
        case .connected(let expiresAt):
            return "Your sessions sync with the dashboard. The connection is valid until \(Self.expiryFormatter.string(from: expiresAt))."
        case .expired:
            return "The connection has expired or was revoked on Polar. Reconnect to keep syncing."
        }
    }

    private static let expiryFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
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
            if failure.pointsToCredentials {
                NavigationLink {
                    PolarCredentialsView(viewModel: makeCredentialsViewModel())
                } label: {
                    Text("Check the application credentials →")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.fbRed)
                }
                .padding(.top, 6)
            }
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

    private var credentialsLink: some View {
        NavigationLink {
            PolarCredentialsView(viewModel: makeCredentialsViewModel())
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "key.horizontal")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.fbAccent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.state == .missingCredentials ? "Enter API application credentials" : "API application credentials")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.fbInk)
                    Text("Client ID and client secret from admin.polaraccesslink.com")
                        .font(.footnote)
                        .foregroundStyle(Color.fbInkSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.fbMuted)
            }
            .padding(14)
            .background(Color.fbCard)
            .clipShape(RoundedRectangle(cornerRadius: FBRadius.control))
            .overlay(
                RoundedRectangle(cornerRadius: FBRadius.control)
                    .strokeBorder(Color.fbBorder, lineWidth: 1)
            )
        }
        .disabled(isAuthorizing)
        .accessibilityIdentifier(AccessibilityID.PolarConnection.credentialsLink)
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
        case .authorizing: return "Waiting for \(PolarKeyPresentation.displayName)…"
        case .connected, .expired: return "Reconnect"
        case .failed: return "Try again"
        case .unknown, .missingCredentials, .idle: return "Connect with \(PolarKeyPresentation.displayName)"
        }
    }
}
