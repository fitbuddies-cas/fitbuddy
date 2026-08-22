import SwiftData
import SwiftUI

@main
struct FitBuddyApp: App {
    /// The app's single SwiftData container, hardened per ADR-001. Created
    /// once at launch and shared with the view hierarchy; `WorkoutStore` is
    /// built from it wherever a sync is triggered.
    private let modelContainer = ModelContainerFactory.makeShared()

    var body: some Scene {
        WindowGroup {
            RootView()
                // Hides API keys in the text field from the app-switcher
                // snapshot (#24).
                .modifier(PrivacyScreenModifier())
        }
        .modelContainer(modelContainer)
    }
}
