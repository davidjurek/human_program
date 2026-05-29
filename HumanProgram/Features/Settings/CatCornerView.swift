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
                    if let uiImage = UIImage(named: photos[index]) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .tag(index)
                            .gesture(swipeDownGesture)
                    }
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .ignoresSafeArea()

            // Top bar: dismiss button
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
    }

    // MARK: - Gestures

    private var swipeDownGesture: some Gesture {
        DragGesture(minimumDistance: 60, coordinateSpace: .global)
            .onEnded { value in
                let verticalAmount = value.translation.height
                let horizontalAmount = abs(value.translation.width)
                if verticalAmount > 80 && verticalAmount > horizontalAmount {
                    selectedIndex = nil
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
