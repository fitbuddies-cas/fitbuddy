import SwiftData
import SwiftUI

// Developer tooling: excluded from Release builds, so the validation log
// view never ships in a TestFlight binary. The log itself is captured and
// stored in every build (#228).
#if DEBUG

/// The developer section at the foot of Settings (#228): one link to the
/// validation log. Its own view so `SettingsView` only has to name it, and
/// so it can reach the model container itself instead of threading a store
/// through the settings initialiser.
///
/// `SettingsView` shows it in debug builds only.
struct AnalysisValidationLogSection: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Section {
            NavigationLink {
                AnalysisValidationLogView(
                    viewModel: AnalysisValidationLogViewModel(
                        store: AnalysisResultStore(modelContainer: modelContext.container)
                    )
                )
            } label: {
                Label("Validation log", systemImage: "list.bullet.clipboard")
                    .font(.subheadline)
                    .foregroundStyle(Color.fbInk)
            }
        } header: {
            Text("DEVELOPER")
                .font(.fbLabel)
                .foregroundStyle(Color.fbMuted)
        } footer: {
            Text("What the app rejected or replaced in each stored AI answer. Debug builds only.")
                .font(.caption)
                .foregroundStyle(Color.fbMuted)
        }
        .listRowBackground(Color.fbCard)
    }
}

#endif
