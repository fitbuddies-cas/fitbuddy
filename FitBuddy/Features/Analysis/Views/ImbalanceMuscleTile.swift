import SwiftUI

/// One of the two muscle groups on the imbalance card: name, frequency and a
/// bar relative to the more frequent group (design 3.4, `MiniMuscle`, #177).
struct ImbalanceMuscleTile: View {
    let bar: ImbalanceBar
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(bar.group.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.fbInk)
                Spacer(minLength: 4)
                Text(AnalysisCardFormatter.perWeek(bar.perWeek))
                    .font(.caption2.weight(.medium))
                    .fbTabularNumbers()
                    .foregroundStyle(Color.fbMuted)
            }
            GeometryReader { geo in
                Capsule()
                    .fill(Color.fbBorder)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(color)
                            .frame(width: geo.size.width * FBBar.clamped(bar.share))
                    }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fbCardSubtle, in: RoundedRectangle(cornerRadius: 10))
    }
}

#if DEBUG
#Preview {
    HStack(spacing: 8) {
        ImbalanceMuscleTile(bar: ImbalanceBar(group: .chest, perWeek: 3, share: 1), color: .fbAccent)
        ImbalanceMuscleTile(bar: ImbalanceBar(group: .legs, perWeek: 1, share: 1.0 / 3), color: .fbWarn)
    }
    .padding(16)
    .background(Color.fbCard)
}
#endif
