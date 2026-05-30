import SwiftUI

struct CatCornerView: View {
    private let photos: [String] = (1...20).compactMap { index in
        let name = String(format: "cat_%02d", index)
        return UIImage(named: name) != nil ? name : nil
    }

    @State private var viewerIndex: Int = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if photos.isEmpty {
                emptyState
            } else {
                // Full-screen photo viewer — swipe horizontally to move between photos.
                TabView(selection: $viewerIndex) {
                    ForEach(photos.indices, id: \.self) { index in
                        ZoomableImageView(imageName: photos[index])
                            .tag(index)
                            // No context menu — prevents save/share on long-press
                            .contextMenu {}
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .interactive))
                .ignoresSafeArea()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 48))
                .foregroundColor(Color.white.opacity(0.25))
            Text("Photos coming soon")
                .foregroundColor(Color.white.opacity(0.35))
                .font(.body)
        }
    }
}

// MARK: - Zoomable image view

// Supports pinch-to-zoom (up to 4x) and double-tap to toggle zoom.
// Uses scaledToFit so each photo keeps its original orientation/aspect ratio
// (portrait photos stay portrait). Does NOT expose any save/share controls.
private struct ZoomableImageView: View {
    let imageName: String

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 4.0

    var body: some View {
        GeometryReader { geo in
            if let uiImage = UIImage(named: imageName) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .frame(width: geo.size.width, height: geo.size.height)
                    // Pinch to zoom
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastScale
                                lastScale = value
                                scale = min(maxScale, max(minScale, scale * delta))
                            }
                            .onEnded { _ in
                                lastScale = 1.0
                                if scale < minScale {
                                    withAnimation(.spring()) { scale = minScale; offset = .zero }
                                }
                            }
                    )
                    // Double-tap to toggle zoom
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.35)) {
                            if scale > 1.1 {
                                scale = 1.0
                                offset = .zero
                            } else {
                                scale = 2.5
                            }
                        }
                    }
                    // Pan when zoomed. The gesture is only active while zoomed in
                    // (mask = .subviews disables it at 1x) so horizontal swipes pass
                    // through to the TabView and paging works on the image itself.
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                guard scale > 1.05 else { return }
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                lastOffset = offset
                                if scale <= 1.05 {
                                    withAnimation(.spring()) { offset = .zero; lastOffset = .zero }
                                }
                            },
                        including: scale > 1.05 ? .all : .subviews
                    )
            }
        }
    }
}

struct CatCornerView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            CatCornerView()
        }
    }
}
