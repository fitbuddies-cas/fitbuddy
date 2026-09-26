import Foundation

extension Error {
    /// Whether this error means "the host answered, but FitBuddy must not
    /// trust it" — as opposed to "the host could not be reached".
    ///
    /// `URLSession` reports a failed certificate-pinning check
    /// (`NSPinnedDomains`, #153) the same way it reports any failed trust
    /// evaluation: as a `URLError` with one of the certificate codes below.
    /// Every transport site maps these onto an `untrustedConnection` case
    /// instead of `networkUnavailable`, because the two ask the user to do
    /// different things — "no connection" sends them looking for reception,
    /// while an untrusted connection means they should check the device
    /// clock or leave the network.
    ///
    /// Only `.serverCertificateUntrusted` and `.serverCertificateHasUnknownRoot`
    /// are what a failed pin check actually produces. The date codes far more
    /// often mean a wrong device clock than an expired certificate, and
    /// `.secureConnectionFailed` is the generic TLS failure (protocol or
    /// cipher mismatch, captive portal, aborted handshake). They stay in the
    /// list because "do not trust, nothing was sent" holds for all five; the
    /// user-facing texts therefore say "could not verify" rather than
    /// asserting interception, and point at date & time as well as the network.
    var isUntrustedConnection: Bool {
        guard let code = (self as? URLError)?.code else { return false }
        switch code {
        case .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .serverCertificateHasBadDate,
             .serverCertificateNotYetValid,
             .secureConnectionFailed:
            return true
        default:
            return false
        }
    }
}
