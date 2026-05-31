import SwiftUI
import UIKit

// Full-screen photo viewer matching the iPhone Photos app: each photo is a
// UIScrollView-backed zoomable view (pinch centered on the pinch point, pan
// while zoomed, double-tap to zoom toward the tap, rubber-band snap-back), and
// a UIPageViewController pages between them with the same inter-photo gap
// Photos shows mid-swipe. Page dots are kept, and hidden while zoomed (Photos
// hides its chrome on zoom). No save/share affordances.

struct CatCornerView: View {
    private let photos: [String] = (1...20).compactMap { index in
        let name = String(format: "cat_%02d", index)
        return UIImage(named: name) != nil ? name : nil
    }

    @State private var currentIndex = 0
    @State private var isZoomed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if photos.isEmpty {
                emptyState
            } else {
                PhotoPager(photos: photos, currentIndex: $currentIndex, isZoomed: $isZoomed)
                    .ignoresSafeArea()

                if photos.count > 1 && !isZoomed {
                    PageDots(count: photos.count, current: currentIndex)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 24)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isZoomed)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

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

// MARK: - Paging container (UIPageViewController)

private struct PhotoPager: UIViewControllerRepresentable {
    let photos: [String]
    @Binding var currentIndex: Int
    @Binding var isZoomed: Bool

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pager = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: 20]   // the gap Photos shows mid-swipe
        )
        pager.dataSource = context.coordinator
        pager.delegate = context.coordinator
        pager.view.backgroundColor = .black
        if let first = context.coordinator.photoVC(at: currentIndex) {
            pager.setViewControllers([first], direction: .forward, animated: false)
        }
        return pager
    }

    func updateUIViewController(_ pager: UIPageViewController, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PhotoPager
        init(_ parent: PhotoPager) { self.parent = parent }

        func photoVC(at index: Int) -> ZoomablePhotoViewController? {
            guard parent.photos.indices.contains(index) else { return nil }
            let vc = ZoomablePhotoViewController(imageName: parent.photos[index], index: index)
            vc.onZoomChange = { [weak self] zoomed in
                guard let self, self.parent.isZoomed != zoomed else { return }
                self.parent.isZoomed = zoomed
            }
            return vc
        }

        func pageViewController(_ pvc: UIPageViewController,
                                viewControllerBefore vc: UIViewController) -> UIViewController? {
            guard let z = vc as? ZoomablePhotoViewController else { return nil }
            return photoVC(at: z.index - 1)
        }

        func pageViewController(_ pvc: UIPageViewController,
                                viewControllerAfter vc: UIViewController) -> UIViewController? {
            guard let z = vc as? ZoomablePhotoViewController else { return nil }
            return photoVC(at: z.index + 1)
        }

        func pageViewController(_ pvc: UIPageViewController, didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard completed, let current = pvc.viewControllers?.first as? ZoomablePhotoViewController else { return }
            parent.currentIndex = current.index
            parent.isZoomed = current.isZoomedIn
        }
    }
}

// MARK: - Single zoomable photo (UIScrollView)

private final class ZoomablePhotoViewController: UIViewController, UIScrollViewDelegate {
    let imageName: String
    let index: Int
    var onZoomChange: ((Bool) -> Void)?

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()

    /// True once zoomed past the fit scale (used to freeze the dots/chrome).
    var isZoomedIn: Bool { scrollView.zoomScale > scrollView.minimumZoomScale * 1.01 }

    init(imageName: String, index: Int) {
        self.imageName = imageName
        self.index = index
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.bouncesZoom = true
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(scrollView)

        imageView.image = UIImage(named: imageName)
        imageView.contentMode = .scaleAspectFit
        scrollView.addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollView.frame = view.bounds
        layoutImageToFit()
    }

    /// Aspect-fit the image at zoom scale 1, then center it.
    private func layoutImageToFit() {
        guard let image = imageView.image, image.size.width > 0, image.size.height > 0 else { return }
        let bounds = scrollView.bounds.size
        guard bounds.width > 0, bounds.height > 0 else { return }
        let fitScale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let fitted = CGSize(width: image.size.width * fitScale, height: image.size.height * fitScale)
        imageView.frame = CGRect(origin: .zero, size: fitted)
        scrollView.contentSize = fitted
        scrollView.setZoomScale(1, animated: false)
        centerImage()
    }

    /// Keep the image centered when it's smaller than the viewport.
    private func centerImage() {
        let bounds = scrollView.bounds.size
        let content = scrollView.contentSize
        let x = max(0, (bounds.width - content.width) / 2)
        let y = max(0, (bounds.height - content.height) / 2)
        scrollView.contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
        onZoomChange?(isZoomedIn)
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        onZoomChange?(isZoomedIn)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if isZoomedIn {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let newScale: CGFloat = 2.5
            let size = scrollView.bounds.size
            let w = size.width / newScale
            let h = size.height / newScale
            let rect = CGRect(x: point.x - w / 2, y: point.y - h / 2, width: w, height: h)
            scrollView.zoom(to: rect, animated: true)
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
