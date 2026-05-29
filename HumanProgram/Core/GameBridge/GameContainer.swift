import SwiftUI

// Polished stub for future game integration. Full-screen black.
// Swipe down or tap X to dismiss.
// Replaced when a real game engine (Unity / Godot) is integrated.
struct GameContainerView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 72, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.12))

                Spacer()

                Text("swipe down to exit")
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(.white.opacity(0.08))
                    .tracking(3)
                    .padding(.bottom, 48)
            }

            // Dismiss button — top-right corner
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.25))
                            .padding(20)
                    }
                }
                Spacer()
            }
        }
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = max(0, value.translation.height)
                }
                .onEnded { value in
                    if value.translation.height > 100 {
                        dismiss()
                    } else {
                        withAnimation(.spring()) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .statusBarHidden(true)
        .navigationBarHidden(true)
    }
}

// MARK: - Preview

#Preview {
    GameContainerView()
}
