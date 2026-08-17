import SwiftUI

/// Covers the wrapped content with `PrivacyScreen` whenever the scene leaves
/// the active phase.
///
/// iOS takes the app-switcher snapshot while the scene is `.inactive`, i.e.
/// *before* it reaches `.background` — so the cover has to react to `.inactive`
/// too, not just `.background`. The transition is deliberately unanimated: an
/// animating overlay can still be mid-fade when the snapshot is taken.
struct PrivacyScreenModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .overlay {
                if scenePhase != .active {
                    PrivacyScreen()
                }
            }
            .animation(nil, value: scenePhase)
    }
}
