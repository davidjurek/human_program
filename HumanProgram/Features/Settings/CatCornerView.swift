import SwiftUI

struct CatCornerView: View {
    private let photos: [String] = (1...20).compactMap { index in
        let name = String(format: "cat_%02d", index)
        return UIImage(named: name) != nil ? name : nil
    }

    /// Inter-photo gutter, like the gap Apple Photos shows mid-swipe. Tunable.
    private let photoGap: CGFloat = 20

    @State private var scrollID: Int?
    @State private var isZoomed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if photos.isEmpty {
                emptyState
            } else {
                // Full-screen photo viewer. A paging ScrollView with a gap
                // between photos: each photo sits full-bleed at rest and the
                // gutter only appears while swiping — Apple Photos behavior.
                // (A TabView page style can't do this; its pages are edge-to-edge.)
                GeometryReader { geo in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: photoGap) {
                            ForEach(photos.indices, id: \.self) { index in
                                ZoomableImageView(imageName: photos[index], isZoomed: $isZoomed)
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .id(index)
                                    // No context menu — prevents save/share on long-press
                                    .contextMenu {}
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .scrollPosition(id: $scrollID)
                    .scrollIndicators(.hidden)
                    // While a photo is zoomed, freeze paging so the drag pans
                    // the photo instead of swiping to the next one.
                    .scrollDisabled(isZoomed)
                }
                .ignoresSafeArea()

                // Page dots (the ScrollView doesn't provide them). Hidden while
                // zoomed, matching the way Apple Photos hides chrome on zoom.
                if photos.count > 1 && !isZoomed {
                    PageDots(count: photos.count, current: scrollID ?? 0)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 24)
                        .allowsHitTesting(false)
                }
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

// MARK: - Page dots

/// Apple-style paging dots: the current photo's dot is bright, the rest dimmed.
private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(index == current ? 0.95 : 0.35))
                    .frame(width: 7, height: 7)
            }
        }
    }
}

// MARK: - Zoomable image view

// Supports pinch-to-zoom (up to 4x) and double-tap to toggle zoom.
// Uses scaledToFit so each photo keeps its original orientation/aspect ratio
// (portrait photos stay portrait). Does NOT expose any save/share controls.
private struct ZoomableImageView: View {
    let imageName: String
    /// Reports up to the pager whether this photo is zoomed, so paging can be
    /// frozen while zoomed (otherwise a pan would swipe to the next photo).
    @Binding var isZoomed: Bool

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
                    // through to the paging ScrollView and move between photos.
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
                    // Keep the pager in sync so it can freeze paging while zoomed.
                    .onChange(of: scale) { _, newValue in
                        isZoomed = newValue > 1.05
                    }
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
