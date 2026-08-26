import SwiftUI

/// The one claim the user cannot verify from the screen itself, so it is stated
/// where the tap happens and again while the request is in flight rather than
/// only in the consent text (US-3 AC3, #32).
///
/// Shared by `AnalysisIntroView` and `AnalysisProgressView`: the wait is when
/// the sentence is worth the most, which is why the design carries it on both.
struct AnalysisPrivacyNote: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock")
                .font(.caption2)
            Text("Only your own training data is sent to Claude — no benchmarks.")
                .font(.caption)
        }
        .foregroundStyle(Color.fbMuted)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    AnalysisPrivacyNote()
        .padding(16)
        .background(Color.fbBackground)
}
#endif
