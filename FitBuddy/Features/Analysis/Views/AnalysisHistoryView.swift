import SwiftUI

/// The list of stored analyses, newest first (US-3 AC11, #117).
///
/// A grouped `List` rather than the card stack the analysis screen uses, for
/// the same reason as `SettingsView`: swipe-to-delete only exists inside a
/// `List`, and deleting a single analysis is this screen's second job. The
/// design-system colors are applied on top of it so it still reads as
/// FitBuddy.
///
/// Pushed onto `AnalysisView`'s own `NavigationStack`, so it inherits the back
/// button and leaves the tab bar in place.
struct AnalysisHistoryView: View {
    @StateObject private var viewModel: AnalysisHistoryViewModel

    /// - Parameter viewModel: Built lazily — the autoclosure is evaluated once,
    ///   when SwiftUI first creates the view's state, so one push builds one
    ///   view model rather than one per row.
    init(viewModel: @autoclosure @escaping () -> AnalysisHistoryViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        content
            .background(Color.fbBackground)
            .navigationTitle("Saved analyses")
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        // A failed read goes to the list, empty or not: it is the only place
        // that renders `failure`, and "No saved analyses" over a store that
        // could not be read tells the user their analyses are gone when they
        // are still on the device.
        if viewModel.entries.isEmpty && viewModel.isLoaded && viewModel.failure == nil {
            emptyState
        } else {
            list
        }
    }

    private var list: some View {
        // One reading of the clock for the whole list, so two rows written a
        // minute apart cannot both claim to be "just now" because they were
        // rendered a moment apart.
        let now = Date()
        return List {
            if let failure = viewModel.failure {
                Section {
                    Text(failure)
                        .font(.footnote)
                        .foregroundStyle(Color.fbRed)
                }
                .listRowBackground(Color.fbRedSoft)
            }
            ForEach(viewModel.entries) { entry in
                NavigationLink {
                    AnalysisHistoryDetailView(entry: entry, now: now)
                } label: {
                    AnalysisHistoryRow(entry: entry, now: now)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await viewModel.delete(id: entry.id) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    /// Reachable after deleting the last row — the entry point only appears
    /// once more than one analysis is stored, so nobody arrives here empty.
    private var emptyState: some View {
        FBCard(padding: 18) {
            FBInfoRow(
                icon: "clock.arrow.circlepath",
                title: "No saved analyses",
                text: "Analyses you run are kept here, so you can compare what the AI told you before."
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

#if DEBUG
#Preview("Filled") {
    NavigationStack {
        AnalysisHistoryView(
            viewModel: AnalysisHistoryViewModel(store: PreviewAnalysisResultStore())
        )
    }
}

#Preview("Empty") {
    NavigationStack {
        AnalysisHistoryView(
            viewModel: AnalysisHistoryViewModel(store: PreviewAnalysisResultStore(entries: []))
        )
    }
}
#endif
