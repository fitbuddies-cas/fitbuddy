import Foundation

/// Abstraction over `DataResetService` so `SettingsViewModel` can be tested
/// without a SwiftData container, and so a test can observe that the full
/// wipe actually ran.
protocol DataResetting: Sendable {
    func deleteAllData() async
}

extension DataResetService: DataResetting {}
