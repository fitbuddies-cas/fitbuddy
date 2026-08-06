import Foundation

extension URL {
    /// Non-optional construction for compile-time constant URLs, so call
    /// sites stay free of force-unwraps. A malformed literal is a programmer
    /// error and traps immediately — any test or preview touching the type
    /// catches it.
    init(staticString: StaticString) {
        guard let url = URL(string: "\(staticString)") else {
            preconditionFailure("Malformed static URL: \(staticString)")
        }
        self = url
    }
}
