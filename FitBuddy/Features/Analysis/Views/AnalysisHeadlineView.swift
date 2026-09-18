import SwiftUI

/// The verdict at the top of a report: "You're ready / to progress." (US-14
/// AC1, design 3.4/3.5, #177).
///
/// The copy comes from `AnalysisHeadline`, never from the model's headline.
struct AnalysisHeadlineView: View {
    let verdict: AnalysisVerdict

    /// 30 pt as in the design, scaled with Dynamic Type from the large title.
    @ScaledMetric(relativeTo: .largeTitle) private var fontSize: CGFloat = 30

    var body: some View {
        Text(AnalysisHeadline.lines(for: verdict).joined(separator: "\n"))
            .font(.system(size: fontSize, weight: .bold))
            .tracking(-0.8)
            .foregroundStyle(Color.fbInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(AnalysisHeadline.text(for: verdict))
            .accessibilityIdentifier(AccessibilityID.Analysis.headline)
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 24) {
        ForEach(AnalysisVerdict.allCases, id: \.self) { verdict in
            AnalysisHeadlineView(verdict: verdict)
        }
    }
    .padding(20)
    .background(Color.fbBackground)
}
#endif
