import Foundation

extension Task where Success == Void, Failure == Never {
    /// Awaits the task, forwarding the caller's cancellation into it.
    ///
    /// Used where work has to stay unstructured — a ViewModel holds on to the
    /// running task so a newer call, or an explicit cancel button, can stop it,
    /// which a child task would not allow. But unstructured also means SwiftUI
    /// tearing down the `.task` that started it leaves the work running: the
    /// request finishes, the result is published to a view nobody is looking
    /// at. This bridges the two.
    func awaitingCancellation() async {
        await withTaskCancellationHandler {
            await value
        } onCancel: {
            cancel()
        }
    }
}
