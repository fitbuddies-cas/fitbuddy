import SwiftUI

/// A labelled stat with a large tabular value, optional unit and delta,
/// matching the `FBStat` primitive from `design/fb-atoms.jsx`.
struct FBStat: View {
    enum DeltaKind {
        case positive, negative, neutral

        var color: Color {
            switch self {
            case .positive: return .fbAccent
            case .negative: return .fbRed
            case .neutral: return .fbMuted
            }
        }
    }

    /// `regular` is the dashboard's headline figure. `compact` fits three
    /// stats side by side inside a card — the recovery card's metrics row
    /// (design 3.5): a smaller uppercase label and an 18-20 pt value.
    enum Size {
        case regular, compact

        var spacing: CGFloat {
            self == .regular ? 6 : 2
        }

        var labelFont: Font {
            self == .regular ? .fbLabel : .caption2.weight(.medium)
        }

        var labelTracking: CGFloat {
            self == .regular ? 0.6 : 0.4
        }

        /// A compact label stays on one line and shrinks a little instead:
        /// "SUGGESTED REST" in a third of a card would otherwise wrap and push
        /// its value below the other two.
        var labelLineLimit: Int? {
            self == .regular ? nil : 1
        }

        var labelMinimumScaleFactor: CGFloat {
            self == .regular ? 1 : 0.8
        }

        var valueFont: Font {
            self == .regular ? .fbStatValue : .title3.weight(.bold)
        }
    }

    let label: String
    let value: String
    var unit: String?
    var delta: String?
    var deltaKind: DeltaKind = .positive
    var size: Size = .regular

    var body: some View {
        VStack(alignment: .leading, spacing: size.spacing) {
            Text(label.uppercased())
                .font(size.labelFont)
                .tracking(size.labelTracking)
                .lineLimit(size.labelLineLimit)
                .minimumScaleFactor(size.labelMinimumScaleFactor)
                .foregroundStyle(Color.fbMuted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(size.valueFont)
                    .fbTabularNumbers()
                    .foregroundStyle(Color.fbInk)
                if let unit {
                    Text(unit)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.fbMuted)
                }
            }
            if let delta {
                Text(delta)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(deltaKind.color)
            }
        }
    }
}
