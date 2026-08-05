import SwiftUI

@main
struct FitBuddyApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                // Hides API keys in the text field from the app-switcher
                // snapshot (#24).
                .modifier(PrivacyScreenModifier())
        }
    }
}
