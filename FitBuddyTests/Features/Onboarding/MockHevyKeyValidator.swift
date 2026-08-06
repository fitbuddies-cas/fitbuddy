import Foundation
@testable import FitBuddy

/// Configurable `HevyKeyValidating` stub recording every validated key.
actor MockHevyKeyValidator: HevyKeyValidating {
    private(set) var receivedKeys: [String] = []
    private var result: Result<Void, Error> = .success(())

    func setResult(_ result: Result<Void, Error>) {
        self.result = result
    }

    func validate(_ apiKey: String) async throws {
        receivedKeys.append(apiKey)
        try result.get()
    }
}
