import SwiftUI

/// Shown when the 90-day window holds no workouts (US-2 AC3).
///
/// Deliberately free of blame: the window is empty both for a user who has not
/// synced yet and for one who did not train, and the dashboard cannot tell the
/// two apart.
struct DashboardEmptyView: View {
    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: FBRadius.grouped)
                .strokeBorder(Color.fbTertiary, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .background(
                    RoundedRectangle(cornerRadius: FBRadius.grouped)
                        .fill(Color.fbCardSubtle)
                )
                .frame(width: 96, height: 96)
                .overlay {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(Color.fbMuted)
                }

            Text("No training data for the last 90 days")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.fbInk)
                .multilineTextAlignment(.center)
                .padding(.top, 22)

            Text("Log a workout in Hevy and pull to refresh. Your dashboard will fill in automatically.")
                .font(.subheadline)
                .foregroundStyle(Color.fbMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            Label("Pull to refresh", systemImage: "arrow.clockwise")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.fbInk)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.fbCard)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Color.fbBorder, lineWidth: 1))
                .padding(.top, 28)
        }
        .padding(.horizontal, 32)
        .padding(.top, 60)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    DashboardEmptyView()
        .frame(maxHeight: .infinity)
        .background(Color.fbBackground)
}
