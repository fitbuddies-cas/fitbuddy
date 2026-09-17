import Foundation

/// UI state of the training profile screen (US-13, step 4).
enum TrainingProfileState: Equatable {
    /// The stored-profile check (`bootstrap()`) has not finished yet.
    case unknown
    /// Waiting for the user's answers.
    case idle
    /// At least one answer was saved — onboarding can move on.
    case saved
    /// The user chose to continue without answering (AC2). The analysis
    /// behaves exactly as it does today.
    case skipped
}
