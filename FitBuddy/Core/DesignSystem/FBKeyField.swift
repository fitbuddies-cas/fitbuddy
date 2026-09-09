import SwiftUI

/// Monospaced API-key input shared by the onboarding key screens: uppercase
/// label, lock icon, 56 pt field with an inline spinner while busy and a red
/// border when the last attempt failed.
struct FBKeyField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var isBusy = false
    var hasError = false
    var focus: FocusState<Bool>.Binding? = nil
    /// Accessibility identifier for the text field itself, so a UI test can
    /// address it without depending on the label or placeholder copy (#120).
    var identifier: String? = nil
    var onSubmit: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.fbLabel)
                .foregroundStyle(Color.fbMuted)
            HStack(spacing: 8) {
                Image(systemName: "lock")
                    .font(.system(size: 14))
                    .foregroundStyle(text.isEmpty ? Color.fbMuted : Color.fbInkSecondary)
                keyTextField
                if isBusy {
                    FBSpinner(size: 18, color: .fbMuted)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 56)
            .background(Color.fbCard)
            .clipShape(RoundedRectangle(cornerRadius: FBRadius.control))
            .overlay(
                RoundedRectangle(cornerRadius: FBRadius.control)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
        }
    }

    @ViewBuilder
    private var keyTextField: some View {
        let field = TextField(placeholder, text: $text)
            .font(.system(.subheadline, design: .monospaced))
            .foregroundStyle(Color.fbInk)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.asciiCapable)
            .submitLabel(.go)
            .disabled(isBusy)
            .onSubmit(onSubmit)
            .accessibilityIdentifier(identifier ?? "")
        if let focus {
            field.focused(focus)
        } else {
            field
        }
    }

    private var borderColor: Color {
        if hasError { return .fbRed }
        return text.isEmpty ? .fbBorder : .fbInk
    }

    private var borderWidth: CGFloat {
        if hasError { return 2 }
        return text.isEmpty ? 1 : 1.5
    }
}
