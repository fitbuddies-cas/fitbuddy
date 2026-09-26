import SwiftUI

/// Developer view of what the validator did to each stored analysis (US-16
/// AC4, #228): the tally across all of them first, then one section per
/// analysis. Reached from the debug section of Settings only.
///
/// No design in `design/` — a developer screen, not a product one. It uses
/// the grouped list and colours of Settings so it does not look foreign, and
/// shows raw enum names on purpose: they are what #229 counts and what the
/// code searches for.
struct AnalysisValidationLogView: View {
    @StateObject private var viewModel: AnalysisValidationLogViewModel

    /// - Parameter viewModel: Built lazily — the autoclosure is evaluated once,
    ///   when SwiftUI first creates the view's state.
    init(viewModel: @autoclosure @escaping () -> AnalysisValidationLogViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        List {
            if let failure = viewModel.failure {
                Section {
                    Text(failure)
                        .font(.footnote)
                        .foregroundStyle(Color.fbRed)
                }
                .listRowBackground(Color.fbRedSoft)
            }
            tallySection
            ForEach(viewModel.entries) { entry in
                entrySection(entry)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.fbBackground)
        .navigationTitle("Validation log")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    private var tallySection: some View {
        Section {
            row("Analyses with a log", value: "\(viewModel.tally.runs)")
            row("Taken as sent", value: "\(viewModel.tally.cleanRuns)")
            row("Verdict overridden", value: "\(viewModel.tally.overriddenVerdicts)")
            row("Without a log", value: "\(viewModel.unrecordedCount)")
            ForEach(viewModel.tally.rows) { tallyRow in
                row("\(tallyRow.subject.rawValue): \(tallyRow.reason.rawValue)", value: "\(tallyRow.count)")
            }
        } header: {
            header("ALL STORED ANALYSES")
        } footer: {
            Text("Prose answers and analyses stored before this log existed have no log.")
                .font(.caption)
                .foregroundStyle(Color.fbMuted)
        }
        .listRowBackground(Color.fbCard)
    }

    private func entrySection(_ entry: AnalysisValidationLogEntry) -> some View {
        Section {
            row("Source", value: AnalysisValidationLogViewModel.source(of: entry.log))
            row("Verdict", value: AnalysisValidationLogViewModel.verdictLine(of: entry.log))
            if entry.log.interventions.isEmpty {
                Text("Nothing rejected")
                    .font(.footnote)
                    .foregroundStyle(Color.fbInkSecondary)
            }
            ForEach(Array(entry.log.interventions.enumerated()), id: \.offset) { _, intervention in
                VStack(alignment: .leading, spacing: 2) {
                    Text(AnalysisValidationLogViewModel.title(of: intervention))
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Color.fbInk)
                    if let figures = AnalysisValidationLogViewModel.figureLine(of: intervention) {
                        Text(figures)
                            .font(.caption)
                            .foregroundStyle(Color.fbInkSecondary)
                    }
                }
            }
        } header: {
            header(entry.generatedAt.formatted(date: .abbreviated, time: .shortened).uppercased())
        }
        .listRowBackground(Color.fbCard)
    }

    private func row(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.footnote)
                .foregroundStyle(Color.fbInk)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Color.fbInkSecondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.fbLabel)
            .foregroundStyle(Color.fbMuted)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        AnalysisValidationLogView(
            viewModel: AnalysisValidationLogViewModel(store: PreviewAnalysisResultStore())
        )
    }
}
#endif
