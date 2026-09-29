import Foundation

/// The launch arguments every `-fb…` seam reads, with a way to keep them past
/// the launch Xcode made.
///
/// A scheme's arguments reach the process only when Xcode starts it. Tapped
/// from the Home screen — the way a demo device is handed around, and the only
/// way Guided Access will wrap an app, since it refuses one under the debugger
/// — the same build comes up without them and asks for a real Hevy key.
///
/// `-fbPersistLaunchArguments` makes a DEBUG launch remember its `-fb…`
/// arguments in `UserDefaults`; a later launch without any `-fb…` argument
/// reads them back. Any Xcode launch *without* the flag forgets them again, so
/// a plain run of the app never inherits a demo's stubs by accident.
/// `-fbResetState` is never remembered: it wipes the defaults it would be
/// stored in, and a reset on every launch is not what a demo wants.
///
/// Release builds return the process arguments unchanged.
enum LaunchArguments {
    #if DEBUG
    static let persistLaunchArgument = "-fbPersistLaunchArguments"
    static let defaultsKey = "fitbuddy.launchArguments.persisted"
    private static let prefix = "-fb"
    #endif

    /// The arguments for this launch: the process's own, or the remembered
    /// ones when the process carries no `-fb…` argument of its own.
    static var current: [String] {
        resolve(process: ProcessInfo.processInfo.arguments, defaults: .standard)
    }

    static func resolve(process: [String], defaults: UserDefaults) -> [String] {
        #if DEBUG
        guard !hasSeamArguments(process) else { return process }
        let remembered = defaults.stringArray(forKey: defaultsKey) ?? []
        return process + remembered
        #else
        return process
        #endif
    }

    /// Remembers or forgets this launch's `-fb…` arguments, depending on the
    /// flag. Call after any forced reset, which would otherwise wipe the entry
    /// this writes.
    static func persistIfRequested(
        process: [String] = ProcessInfo.processInfo.arguments,
        defaults: UserDefaults = .standard
    ) {
        #if DEBUG
        guard hasSeamArguments(process) else { return }
        guard process.contains(persistLaunchArgument) else {
            defaults.removeObject(forKey: defaultsKey)
            return
        }
        defaults.set(seamArguments(in: process), forKey: defaultsKey)
        #endif
    }

    #if DEBUG
    private static func hasSeamArguments(_ arguments: [String]) -> Bool {
        arguments.contains { $0.hasPrefix(prefix) }
    }

    /// Every `-fb…` flag with its value, minus the persist flag itself and
    /// the reset flag.
    private static func seamArguments(in arguments: [String]) -> [String] {
        var kept: [String] = []
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]
            index = arguments.index(after: index)
            guard argument.hasPrefix(prefix) else { continue }
            guard argument != persistLaunchArgument,
                  argument != FirstLaunchResetService.resetLaunchArgument else { continue }
            kept.append(argument)
            if index < arguments.endIndex, !arguments[index].hasPrefix("-") {
                kept.append(arguments[index])
                index = arguments.index(after: index)
            }
        }
        return kept
    }
    #endif
}
