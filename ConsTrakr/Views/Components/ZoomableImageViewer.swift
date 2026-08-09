//
//  ZoomableImageViewer.swift
//  ConsTrakr
//
//  Full-screen photo viewer with pinch/double-tap zoom and swipe to dismiss.
//

import SwiftUI
import UIKit

// MARK: - UIKit photo browser

final class PhotoViewerViewController: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    private let image: UIImage
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()

    var onSingleTap: (() -> Void)?
    var onDismiss: (() -> Void)?

    private var fittedImageSize: CGSize = .zero
    private var isDismissDragging = false

    init(image: UIImage) {
        self.image = image
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        scrollView.delegate = self
        scrollView.backgroundColor = .clear
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.bouncesZoom = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)

        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        let dismissPan = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
        dismissPan.delegate = self
        view.addGestureRecognizer(dismissPan)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !isDismissDragging else { return }
        configureImageLayout()
    }

    override var prefersStatusBarHidden: Bool { true }

    private func configureImageLayout() {
        let bounds = scrollView.bounds.size
        guard bounds.width > 1, bounds.height > 1 else { return }

        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let widthScale = bounds.width / imageSize.width
        let heightScale = bounds.height / imageSize.height
        let fitScale = min(widthScale, heightScale)
        let fitSize = CGSize(width: imageSize.width * fitScale, height: imageSize.height * fitScale)

        guard fitSize != fittedImageSize else {
            centerImageInScrollView()
            return
        }

        fittedImageSize = fitSize
        scrollView.zoomScale = 1
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4

        imageView.frame = CGRect(origin: .zero, size: fitSize)
        scrollView.contentSize = fitSize
        centerImageInScrollView()
    }

    private func centerImageInScrollView() {
        let boundsSize = scrollView.bounds.size
        let contentSize = scrollView.contentSize
        let insetX = max((boundsSize.width - contentSize.width) * 0.5, 0)
        let insetY = max((boundsSize.height - contentSize.height) * 0.5, 0)
        scrollView.contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImageInScrollView()
    }

    @objc private func handleSingleTap() {
        onSingleTap?()
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale + 0.05 {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            return
        }

        let location = recognizer.location(in: imageView)
        let targetScale = min(scrollView.maximumZoomScale, 2.5)
        let zoomRectSize = CGSize(
            width: scrollView.bounds.width / targetScale,
            height: scrollView.bounds.height / targetScale
        )
        let zoomRect = CGRect(
            x: location.x - zoomRectSize.width * 0.5,
            y: location.y - zoomRectSize.height * 0.5,
            width: zoomRectSize.width,
            height: zoomRectSize.height
        )
        scrollView.zoom(to: zoomRect, animated: true)
    }

    @objc private func handleDismissPan(_ recognizer: UIPanGestureRecognizer) {
        guard scrollView.zoomScale <= scrollView.minimumZoomScale + 0.05 else { return }

        let translation = recognizer.translation(in: view)
        switch recognizer.state {
        case .began:
            isDismissDragging = true
        case .changed:
            let offsetY = max(0, translation.y)
            view.transform = CGAffineTransform(translationX: 0, y: offsetY)
            view.backgroundColor = UIColor.black.withAlphaComponent(1 - min(1, offsetY / 240) * 0.5)
        case .ended, .cancelled:
            let velocity = recognizer.velocity(in: view).y
            if translation.y > 100 || velocity > 800 {
                onDismiss?()
            } else {
                UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
                    self.view.transform = .identity
                    self.view.backgroundColor = .black
                } completion: { _ in
                    self.isDismissDragging = false
                }
            }
        default:
            break
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard scrollView.zoomScale <= scrollView.minimumZoomScale + 0.05 else { return false }
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: view)
        return velocity.y > abs(velocity.x) && velocity.y > 0
    }
}

// MARK: - SwiftUI bridge

private struct PhotoBrowser: UIViewControllerRepresentable {
    let image: UIImage
    let onSingleTap: () -> Void
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> PhotoViewerViewController {
        let controller = PhotoViewerViewController(image: image)
        controller.onSingleTap = onSingleTap
        controller.onDismiss = onDismiss
        return controller
    }

    func updateUIViewController(_ uiViewController: PhotoViewerViewController, context: Context) {
        uiViewController.onSingleTap = onSingleTap
        uiViewController.onDismiss = onDismiss
    }
}

struct PhotoLightboxView: View {
    @Environment(\.dismiss) private var dismiss

    let image: UIImage
    let title: String

    @State private var showChrome = true

    var body: some View {
        ZStack(alignment: .top) {
            PhotoBrowser(image: image, onSingleTap: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showChrome.toggle()
                }
            }, onDismiss: {
                dismiss()
            })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()

            if showChrome {
                topChrome
                    .transition(.opacity)
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
    }

    private var topChrome: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Close")

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .top)
        .background {
            LinearGradient(
                colors: [Color.black.opacity(0.7), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        }
    }
}

// MARK: - Swipeable gallery

struct PhotoGalleryItem: Identifiable {
    let id: String
    let image: UIImage
    let title: String
}

final class PhotoGalleryViewController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    private let viewers: [PhotoViewerViewController]
    private(set) var currentIndex: Int

    var onIndexChange: ((Int) -> Void)?
    var onSingleTap: (() -> Void)?
    var onDismiss: (() -> Void)?

    init(items: [PhotoGalleryItem], initialIndex: Int) {
        viewers = items.map { PhotoViewerViewController(image: $0.image) }
        currentIndex = items.isEmpty ? 0 : min(max(0, initialIndex), items.count - 1)
        super.init(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [UIPageViewController.OptionsKey.interPageSpacing: 12]
        )
        super.dataSource = self
        super.delegate = self

        for viewer in viewers {
            viewer.onSingleTap = { [weak self] in self?.onSingleTap?() }
            viewer.onDismiss = { [weak self] in self?.onDismiss?() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        if let first = viewers[safe: currentIndex] {
            setViewControllers([first], direction: .forward, animated: false)
        }
    }

    override var prefersStatusBarHidden: Bool { true }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard
            let viewer = viewController as? PhotoViewerViewController,
            let index = viewers.firstIndex(where: { $0 === viewer }),
            index > 0
        else { return nil }
        return viewers[index - 1]
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard
            let viewer = viewController as? PhotoViewerViewController,
            let index = viewers.firstIndex(where: { $0 === viewer }),
            index + 1 < viewers.count
        else { return nil }
        return viewers[index + 1]
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard
            completed,
            let viewer = viewControllers?.first as? PhotoViewerViewController,
            let index = viewers.firstIndex(where: { $0 === viewer }),
            index != currentIndex
        else { return }
        currentIndex = index
        onIndexChange?(index)
    }
}

private struct PhotoGalleryBrowser: UIViewControllerRepresentable {
    let items: [PhotoGalleryItem]
    let initialIndex: Int
    @Binding var currentIndex: Int
    let onSingleTap: () -> Void
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> PhotoGalleryViewController {
        let controller = PhotoGalleryViewController(items: items, initialIndex: initialIndex)
        controller.onIndexChange = { index in
            currentIndex = index
        }
        controller.onSingleTap = onSingleTap
        controller.onDismiss = onDismiss
        return controller
    }

    func updateUIViewController(_ uiViewController: PhotoGalleryViewController, context: Context) {
        uiViewController.onSingleTap = onSingleTap
        uiViewController.onDismiss = onDismiss
    }
}

struct PhotoGalleryLightboxView: View {
    @Environment(\.dismiss) private var dismiss

    let items: [PhotoGalleryItem]
    let initialIndex: Int

    @State private var currentIndex: Int
    @State private var showChrome = true

    init(items: [PhotoGalleryItem], initialIndex: Int = 0) {
        self.items = items
        let clamped = items.isEmpty ? 0 : min(max(0, initialIndex), items.count - 1)
        self.initialIndex = clamped
        _currentIndex = State(initialValue: clamped)
    }

    var body: some View {
        ZStack {
            PhotoGalleryBrowser(
                items: items,
                initialIndex: initialIndex,
                currentIndex: $currentIndex,
                onSingleTap: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showChrome.toggle()
                    }
                },
                onDismiss: {
                    dismiss()
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()

            if showChrome {
                VStack(spacing: 0) {
                    topChrome
                    Spacer(minLength: 0)
                    if items.count > 1 {
                        pageIndicator
                    }
                }
                .transition(.opacity)
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
    }

    private var topChrome: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Close")

            VStack(alignment: .leading, spacing: 2) {
                Text(items[safe: currentIndex]?.title ?? "")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if items.count > 1 {
                    Text("\(currentIndex + 1) of \(items.count)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .top)
        .background {
            LinearGradient(
                colors: [Color.black.opacity(0.7), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(items.indices, id: \.self) { index in
                Circle()
                    .fill(index == currentIndex ? Color.white : Color.white.opacity(0.35))
                    .frame(width: index == currentIndex ? 7 : 6, height: index == currentIndex ? 7 : 6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
        .accessibilityLabel("Photo \(currentIndex + 1) of \(items.count)")
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
