import SwiftUI

/// Button style matching the `FBButton` primitive from `design/fb-atoms.jsx`.
/// Full-width by default, 52 pt tall, `FBRadius.control` corners, with a subtle
/// press animation. Pick a `kind` for the visual treatment. A disabled button
/// is dimmed (opacity 0.4) so it reads as non-interactive, matching the design.
struct FBButtonStyle: ButtonStyle {
    enum Kind {
        case primary, accent, secondary, ghost, danger
    }

    var kind: Kind = .primary
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        // Routed through an inner view so the style can read `isEnabled` from
        // the environment (a ButtonStyle's configuration does not expose it).
        FBButtonBody(kind: kind, fullWidth: fullWidth, configuration: configuration)
    }

    private struct FBButtonBody: View {
        @Environment(\.isEnabled) private var isEnabled

        let kind: Kind
        let fullWidth: Bool
        let configuration: Configuration

        var body: some View {
            configuration.label
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .frame(height: 52)
                .padding(.horizontal, fullWidth ? 0 : 20)
                .background(background)
                .overlay(
                    RoundedRectangle(cornerRadius: FBRadius.control)
                        .strokeBorder(border, lineWidth: borderWidth)
                )
                .clipShape(RoundedRectangle(cornerRadius: FBRadius.control))
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }

        private var foreground: Color {
            switch kind {
            // `fbInk` flips to an off-white surface in dark mode, so the label
            // must use the inverse surface (`fbBackground`) to stay legible in
            // both appearances — a fixed white would vanish on the dark-mode
            // (light) button.
            case .primary: return .fbBackground
            // The accent stays green in both appearances, so white keeps contrast.
            case .accent: return .white
            case .secondary, .ghost: return .fbInk
            case .danger: return .fbRed
            }
        }

        private var background: Color {
            switch kind {
            case .primary: return .fbInk
            case .accent: return .fbAccent
            case .secondary: return .fbCardSubtle
            case .ghost: return .clear
            case .danger: return .fbRedSoft
            }
        }

        private var border: Color {
            switch kind {
            case .secondary, .ghost: return .fbBorder
            case .danger: return .fbRed.opacity(0.2)
            default: return .clear
            }
        }

        private var borderWidth: CGFloat {
            switch kind {
            case .primary, .accent: return 0
            default: return 1
            }
        }
    }
}

extension ButtonStyle where Self == FBButtonStyle {
    /// `Button("…") { }.buttonStyle(.fb(.primary))`
    static func fb(_ kind: FBButtonStyle.Kind = .primary, fullWidth: Bool = true) -> FBButtonStyle {
        FBButtonStyle(kind: kind, fullWidth: fullWidth)
    }
}
