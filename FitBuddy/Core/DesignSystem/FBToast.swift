import SwiftUI

/// Transient message that sits over the content and leaves on its own.
///
/// The design system's answer to feedback the user does not have to
/// acknowledge: unlike an alert it takes no tap to get rid of and blocks
/// nothing underneath, which is what makes it usable for a failed refresh —
/// the cached dashboard has to stay readable behind it (US-10 AC2).
struct FBToast: View {
    let symbolName: String
    let message: String
    /// How long it stays up before dismissing itself.
    var duration: Duration = .seconds(5)
    /// Called on the timeout and on a tap. The owner clears its state here;
    /// the toast never hides itself behind the owner's back.
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.fbWarn)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.fbInk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fbCard)
        .clipShape(RoundedRectangle(cornerRadius: FBRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: FBRadius.card)
                .strokeBorder(Color.fbWarn.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 12, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: FBRadius.card))
        .onTapGesture(perform: onDismiss)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityAction(named: "Dismiss", onDismiss)
        // Restarts whenever the caller gives the toast a new identity, so a
        // second message gets its own full duration instead of inheriting
        // what was left of the first one's.
        .task {
            // The only feedback a repeated failure gives, so it has to reach
            // VoiceOver too: the toast takes no focus and is gone in 5 s.
            AccessibilityNotification.Announcement(message).post()
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            onDismiss()
        }
    }
}

#if DEBUG
#Preview("Toast") {
    VStack {
        Spacer()
        FBToast(
            symbolName: "antenna.radiowaves.left.and.right.slash",
            message: "No connection. Your cached data is still here.",
            onDismiss: {}
        )
        FBToast(
            symbolName: "exclamationmark.icloud",
            message: "Too many requests to Hevy. Try again in 3 min.",
            onDismiss: {}
        )
    }
    .padding(16)
    .background(Color.fbBackground)
}
#endif
