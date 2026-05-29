import SwiftUI

// Stub game container — replaced when a real game engine is integrated.
// Shown after the puzzle gate is solved.
struct GameContainerView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Text("Game")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.white.opacity(0.4))
                Text("Coming soon.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.2))
            }
        }
    }
}
