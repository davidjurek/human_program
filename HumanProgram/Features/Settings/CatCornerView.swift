import SwiftUI

struct CatCornerView: View {
    private let photos: [String] = (1...20).compactMap { index in
        let name = String(format: "cat_%02d", index)
        return UIImage(named: name) != nil ? name : nil
    }

    @State private var selectedIndex: Int? = nil
    @State private var viewerIndex: Int = 0

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if photos.isEmpty {
                emptyState
            } else {
                gridView
            }

            if selectedIndex != nil {
                viewerOverlay
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
                .font(AppTypography.body)
        }
    }

    // MARK: - Grid

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(photos.indices, id: \.self) { index in
                    GridCell(imageName: photos[index])
                        .onTapGesture {
                            viewerIndex = index
                            selectedIndex = index
                        }
                        // Disable long-press context menu so system "Save Image" never appears
                        .contextMenu {}
                }
            }
        }
    }

    // MARK: - Viewer

    @ViewBuilder
    private var viewerOverlay: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            TabView(selection: $viewerIndex) {
                ForEach(photos.indices, id: \.self) { index in
                    ZoomableImageView(imageName: photos[index])
                        .tag(index)
                        // No context menu — prevents save/share from appearing on long-press
                        .contextMenu {}
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .ignoresSafeArea()

            // Top bar: dismiss
            HStack {
                Spacer()
                Button {
                    selectedIndex = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                }
                .padding(.top, 56)
                .padding(.trailing, 20)
            }

            // Bottom page indicator
            VStack {
                Spacer()
                Text("\(viewerIndex + 1) / \(photos.count)")
                    .font(AppTypography.caption())
                    .foregroundColor(Color.white.opacity(0.5))
                    .padding(.bottom, 36)
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: selectedIndex)
        .gesture(
            DragGesture(minimumDistance: 60, coordinateSpace: .global)
                .onEnded { value in
                    if value.translation.height > 80,
                       value.translation.height > abs(value.translation.width) {
                        selectedIndex = nil
                    }
                }
        )
    }
}

// MARK: - Zoomable image view

// Supports pinch-to-zoom (up to 4x) and double-tap to toggle zoom.
// Does NOT expose any save/share controls.
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
                    // Pan when zoomed
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
                                // Snap back if dragged too far
                                if scale <= 1.05 {
                                    withAnimation(.spring()) { offset = .zero; lastOffset = .zero }
                                }
                            }
                    )
            }
        }
    }
}

// MARK: - Grid Cell

private struct GridCell: View {
    let imageName: String

    var body: some View {
        GeometryReader { geo in
            if let uiImage = UIImage(named: imageName) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.width)
                    .clipped()
                    .cornerRadius(4)
            } else {
                Color.gray.opacity(0.2)
                    .frame(width: geo.size.width, height: geo.size.width)
                    .cornerRadius(4)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct CatCornerView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            CatCornerView()
                .navigationTitle("Cat Corner")
        }
    }
}
