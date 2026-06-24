import SwiftUI

/// A title + explanatory paragraph with an optional leading SF Symbol. Shared by
/// the consent disclosures and the privacy-policy sections (replaces the row
/// builders that were duplicated across both onboarding screens).
struct FBInfoRow: View {
    var icon: String?
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Color.fbAccent)
                    .frame(width: 28)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.fbTitle)
                    .foregroundStyle(Color.fbInk)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Color.fbInkSecondary)
            }
        }
    }
}
