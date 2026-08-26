import Foundation

/// Abstraction over `SessionResetService` so `SettingsViewModel` can be tested
/// without a SwiftData container, and so a test can observe that the hard
/// logout actually ran.
protocol SessionResetting: Sendable {
    func hardLogout() async
}

extension SessionResetService: SessionResetting {}
