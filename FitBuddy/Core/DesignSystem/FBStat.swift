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

    let label: String
    let value: String
    var unit: String?
    var delta: String?
    var deltaKind: DeltaKind = .positive

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.fbLabel)
                .tracking(0.6)
                .foregroundStyle(Color.fbMuted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.fbStatValue)
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
