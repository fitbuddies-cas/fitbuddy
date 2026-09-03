import SwiftUI

/// Opaque cover shown while the app is not active, so iOS snapshots this
/// instead of the live UI for the app switcher.
///
/// Without it, backgrounding the app on an onboarding screen would persist a
/// snapshot containing the API key in the text field to disk, where it is
/// readable outside the Keychain's protection class.
struct PrivacyScreen: View {
    var body: some View {
        ZStack {
            Color.fbBackground
            VStack(spacing: 12) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.fbAccent)
                Text("FitBuddy")
                    .font(.title2.bold())
                    .foregroundStyle(Color.fbInk)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

#Preview {
    PrivacyScreen()
}
