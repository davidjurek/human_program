import SwiftUI

struct CompletionBannerView: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(AppColors.accentGreen)
            Text("Congratulations, you are done for the day!")
                .font(AppTypography.completionMessage())
                .foregroundStyle(AppColors.accentGreen)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.accentGreen.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
    }
}
