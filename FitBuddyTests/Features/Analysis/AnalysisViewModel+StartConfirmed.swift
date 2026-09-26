import Foundation
@testable import FitBuddy

extension AnalysisViewModel {
    /// What the user does to start a run since #268: tap "Analyze with AI",
    /// tick the box on the sheet, tap "Send & analyze". The run's own tests
    /// are about what happens after that, so they go through here.
    ///
    /// The sheet's `load()` is not called: the tests hand in no provider
    /// keys, and the run under test does not depend on the list.
    func startConfirmed() async {
        requestStart()
        sendConfirmation?.hasConfirmedCheckbox = true
        await confirmSend()
    }
}
