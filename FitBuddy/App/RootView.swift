import SwiftUI

/// Platzhalter-Root-View. Wird durch den Onboarding-Flow (#20–24) ersetzt.
struct RootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("FitBuddy")
                .font(.largeTitle.bold())
            Text("PoC-Skelett – bereit für Sprint 1")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    RootView()
}
