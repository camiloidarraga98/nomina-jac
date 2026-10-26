#if os(iOS)
import SwiftUI
import UIKit
import ImageIO

/// Displays only authorized local documents supplied by the owner. The pager
/// never fetches a URL and retains at most the selected bitmap and its neighbors.
struct MediaFullscreenPhotoPager: UIViewRepresentable {
    let items: [MediaItem]
    let selectedID: String
    let documents: [String: URL]
    let progress: [String: Double]
    let errors: [String: String]
    let active: Bool
    let select: (String) -> Void
    let retry: (String) -> Void
    var savePhoto: ((MediaItem) -> Void)? = nil
    var dismissPhoto: (() -> Void)? = nil

    func makeUIView(context: Context) -> MediaFullscreenPhotoPagerView {
        MediaFullscreenPhotoPagerView()
    }

    func updateUIView(_ view: MediaFullscreenPhotoPagerView, context: Context) {
        view.configure(items: items, selectedID: selectedID, documents: documents,
                       progress: progress, errors: errors, active: active,
                       select: select, retry: retry, savePhoto: savePhoto, dismissPhoto: dismissPhoto)
    }

    static func dismantleUIView(_ view: MediaFullscreenPhotoPagerView, coordinator: ()) {
        view.stop()
    }
}

final class MediaFullscreenPhotoPagerView: UIView, UIScrollViewDelegate, UIContextMenuInteractionDelegate, UIGestureRecognizerDelegate {
    private let pager = UIScrollView()
    private var items: [MediaItem] = []
    private var documents: [String: URL] = [:]
    private var progress: [String: Double] = [:]
    private var errors: [String: String] = [:]
    private var selectedID = ""
    private var lastInputSelection = ""
    private var visibleIDs: [String] = []
    private var pages: [String: MediaFullscreenPhotoPage] = [:]
    private var viewport = CGSize.zero
    private var enabled = false
    private var epoch = UUID()
    private var select: ((String) -> Void)?
    private var retry: ((String) -> Void)?
    private var savePhoto: ((MediaItem) -> Void)?
    private var dismissPhoto: (() -> Void)?
    private lazy var verticalPan = UIPanGestureRecognizer(target:self,action:#selector(dragToDismiss(_:)))
    private var decoding: Task<UIImage?, Never>?
    private var decodeCompletion: Task<Void, Never>?
    private var changingWindow = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        pager.delegate = self
        pager.isPagingEnabled = true
        pager.bounces = false
        pager.alwaysBounceHorizontal = false
        pager.alwaysBounceVertical = false
        pager.showsHorizontalScrollIndicator = false
        pager.showsVerticalScrollIndicator = false
        pager.scrollsToTop = false
        pager.contentInsetAdjustmentBehavior = .never
        pager.panGestureRecognizer.maximumNumberOfTouches = 1
        pager.accessibilityIdentifier = "media.photo.pager"
        addSubview(pager)
        addInteraction(UIContextMenuInteraction(delegate:self))
        verticalPan.delegate=self;verticalPan.maximumNumberOfTouches=1
        addGestureRecognizer(verticalPan)
        pager.panGestureRecognizer.require(toFail:verticalPan)
        accessibilityIdentifier = "media.photo.viewer"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        decoding?.cancel()
        decodeCompletion?.cancel()
    }

    func configure(items: [MediaItem], selectedID: String, documents: [String: URL],
                   progress: [String: Double], errors: [String: String], active: Bool,
                   select: @escaping (String) -> Void, retry: @escaping (String) -> Void, savePhoto: ((MediaItem) -> Void)? = nil, dismissPhoto: (() -> Void)? = nil) {
        guard active else { stop(); return }
        if !enabled { enabled = true; epoch = UUID(); pager.isHidden = false }
        self.select = select
        self.retry = retry
        self.savePhoto = savePhoto
        self.dismissPhoto = dismissPhoto
        var seen = Set<String>()
        self.items = items.filter { $0.kind == "image" && seen.insert($0.id).inserted }
        self.documents = documents
        self.progress = progress
        self.errors = errors
        let changedSelection = lastInputSelection != selectedID
        lastInputSelection = selectedID
        if changedSelection || !self.items.contains(where: { $0.id == self.selectedID }) {
            self.selectedID = self.items.contains(where: { $0.id == selectedID }) ? selectedID : (self.items.first?.id ?? "")
            endInteraction()
            updateWindow(force: true)
        } else if !pager.isDragging && !pager.isDecelerating {
            updateWindow()
        }
        updatePages()
        scheduleDecode()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard viewport != bounds.size else { return }
        viewport = bounds.size
        endInteraction()
        pager.frame = bounds
        layoutPages(centerSelection: true)
    }

    func stop() {
        enabled = false
        savePhoto = nil
        dismissPhoto = nil
        pager.transform = .identity;pager.alpha=1
        epoch = UUID()
        pager.isHidden = true
        pager.isScrollEnabled = false
        decoding?.cancel()
        decodeCompletion?.cancel()
        // Keep an in-flight decoder serial until it finishes. A resumed view
        // waits for that result to be discarded before scheduling another one.
        pages.values.forEach { $0.stop(); $0.removeFromSuperview() }
        pages = [:]
        visibleIDs = []
        items = []
        documents = [:]
        progress = [:]
        errors = [:]
        selectedID = ""
        lastInputSelection = ""
        select = nil
        retry = nil
    }
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard enabled, let item=items.first(where:{$0.id==selectedID}), documents[item.id] != nil, let savePhoto else { return nil }
        return UIContextMenuConfiguration(identifier:item.id as NSString,previewProvider:nil) { [weak self] _ in
            UIMenu(children:[UIAction(title:"Guardar en Fotos",image:UIImage(systemName:"square.and.arrow.down")) { [weak self] _ in
                guard let self,self.enabled,self.items.contains(where:{$0.id==item.id && $0.modifiedAt==item.modifiedAt}) else { return }
                savePhoto(item)
            }])
        }
    }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === verticalPan else { return true }
        let velocity=verticalPan.velocity(in:self)
        return enabled && dismissPhoto != nil && !(pages[selectedID]?.isMagnified ?? false) && abs(velocity.y)>abs(velocity.x)*1.25
    }
    @objc private func dragToDismiss(_ gesture: UIPanGestureRecognizer) {
        let translation=gesture.translation(in:self),distance=abs(translation.y)
        switch gesture.state {
        case .began,.changed:
            let scale=max(0.75,1-distance/max(1,bounds.height)*0.35)
            pager.transform=CGAffineTransform(translationX:translation.x*0.15,y:translation.y).scaledBy(x:scale,y:scale)
            pager.alpha=max(0.3,1-distance/max(1,bounds.height))
        case .ended:
            if distance>90 || abs(gesture.velocity(in:self).y)>800 { dismissPhoto?() }
            else { UIView.animate(withDuration:0.2) {self.pager.transform = .identity;self.pager.alpha=1} }
        case .cancelled,.failed:
            UIView.animate(withDuration:0.2) {self.pager.transform = .identity;self.pager.alpha=1}
        default: break
        }
    }

    private func endInteraction() {
        let wasChanging = changingWindow
        changingWindow = true
        if pager.isDragging || pager.isDecelerating {
            pager.panGestureRecognizer.isEnabled = false
            pager.panGestureRecognizer.isEnabled = true
        }
        pager.setContentOffset(pager.contentOffset, animated: false)
        changingWindow = wasChanging
    }

    private func desiredWindow() -> [String] {
        guard let index = items.firstIndex(where: { $0.id == selectedID }) else { return [] }
        return Array(items[max(0, index - 1)...min(items.count - 1, index + 1)]).map(\.id)
    }

    private func updateWindow(force: Bool = false) {
        let wanted = desiredWindow()
        guard force || wanted != visibleIDs else { return }
        changingWindow = true
        for id in visibleIDs where !wanted.contains(id) {
            pages.removeValue(forKey: id)?.removeAndStop()
        }
        visibleIDs = wanted
        for id in visibleIDs where pages[id] == nil {
            let page = MediaFullscreenPhotoPage()
            page.zoomChanged = { [weak self] in self?.updatePagingAvailability() }
            page.retry = { [weak self] in self?.retryPage(id) }
            page.advance = { [weak self] delta in self?.advance(delta) }
            pages[id] = page
            pager.addSubview(page)
        }
        updatePages()
        layoutPages(centerSelection: true)
        changingWindow = false
    }

    private func layoutPages(centerSelection: Bool) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        changingWindow = true
        for (slot, id) in visibleIDs.enumerated() {
            pages[id]?.frame = CGRect(x: CGFloat(slot) * bounds.width, y: 0, width: bounds.width, height: bounds.height)
        }
        pager.contentSize = CGSize(width: CGFloat(visibleIDs.count) * bounds.width, height: bounds.height)
        if centerSelection, let slot = visibleIDs.firstIndex(of: selectedID) {
            pager.setContentOffset(CGPoint(x: CGFloat(slot) * bounds.width, y: 0), animated: false)
        }
        updatePagingAvailability()
        changingWindow = false
    }

    private func updatePages() {
        for id in visibleIDs {
            guard let item = items.first(where: { $0.id == id }), let page = pages[id] else { continue }
            page.configure(item: item, url: documents[id], progress: progress[id], error: errors[id], selected: id == selectedID)
        }
        updatePagingAvailability()
    }

    private func updatePagingAvailability() {
        pager.isScrollEnabled = enabled && visibleIDs.count > 1 && !(pages[selectedID]?.isMagnified ?? false)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { settleSelection() }
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { settleSelection() }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { settleSelection() }
    }

    private func settleSelection() {
        guard enabled, !changingWindow, bounds.width > 0, !visibleIDs.isEmpty else { return }
        let slot = min(visibleIDs.count - 1, max(0, Int((pager.contentOffset.x / bounds.width).rounded())))
        let next = visibleIDs[slot]
        if next != selectedID {
            selectedID = next
            updateWindow(force: true)
            scheduleDecode()
            select?(next)
            if UIAccessibility.isVoiceOverRunning, let item = items.first(where: { $0.id == next }) {
                UIAccessibility.post(notification: .pageScrolled, argument: item.name)
            }
        } else {
            updateWindow()
            layoutPages(centerSelection: true)
            scheduleDecode()
        }
    }

    private func advance(_ delta: Int) {
        guard enabled, !pager.isDragging, !pager.isDecelerating,
              let index = items.firstIndex(where: { $0.id == selectedID }),
              items.indices.contains(index + delta), let slot = visibleIDs.firstIndex(of: items[index + delta].id) else { return }
        pages[selectedID]?.resetZoom()
        pager.setContentOffset(CGPoint(x: CGFloat(slot) * bounds.width, y: 0), animated: !UIAccessibility.isReduceMotionEnabled)
        if UIAccessibility.isReduceMotionEnabled { settleSelection() }
    }

    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        let delta: Int
        switch direction {
        case .up,.down: guard enabled,let dismissPhoto else {return false};dismissPhoto();return true
        case .left, .next: delta = 1
        case .right, .previous: delta = -1
        default: return false
        }
        guard let index = items.firstIndex(where: { $0.id == selectedID }), items.indices.contains(index + delta) else { return false }
        advance(delta)
        return true
    }

    private func retryPage(_ id: String) {
        pages[id]?.prepareRetry()
        retry?(id)
        scheduleDecode()
    }

    private func scheduleDecode() {
        guard enabled, decoding == nil else { return }
        let ordered = [selectedID] + visibleIDs.reversed().filter { $0 != selectedID }
        guard let id = ordered.first(where: { pages[$0]?.needsDecode == true }),
              let page = pages[id], let url = page.sourceURL else { return }
        // A replacement decode also owns a bitmap. Keep room for it without
        // blanking the selected, already visible lower-resolution photo.
        if pages.values.filter({ $0.hasBitmap }).count >= 3 {
            if id != selectedID, page.hasBitmap { page.releaseBitmap() }
            else if let neighbor = visibleIDs.first(where: { $0 != selectedID && pages[$0]?.hasBitmap == true }) {
                pages[neighbor]?.releaseBitmap()
            }
        }
        let pageToken = page.requestToken
        let edge = page.targetEdge
        let expectedEpoch = epoch
        let worker = Task.detached(priority: .userInitiated) { Self.decode(url, edge: edge) }
        decoding = worker
        decodeCompletion = Task { [weak self] in
            let image = await worker.value
            guard let self else { return }
            self.decoding = nil
            self.decodeCompletion = nil
            if self.enabled, self.epoch == expectedEpoch, let page = self.pages[id], page.requestToken == pageToken, page.sourceURL == url, page.targetEdge == edge {
                page.install(image, edge: edge)
            }
            self.scheduleDecode()
        }
    }

    nonisolated private static func decode(_ url: URL, edge: Int) -> UIImage? {
        autoreleasepool {
            guard url.isFileURL, !Task.isCancelled,
                  let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: edge,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary), !Task.isCancelled else { return nil }
            return UIImage(cgImage: bitmap)
        }
    }
}

private final class MediaFullscreenPhotoPage: UIView, UIScrollViewDelegate {
    private let zoom = UIScrollView()
    private let image = MediaPagerAccessibleImage()
    private let status = UIStackView()
    private let ring = MediaPhotoProgressRing()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let message = UILabel()
    private let retryButton = UIButton(type: .system)
    private var viewport = CGSize.zero
    private var name = ""
    private var representedID = ""
    private var remoteError: String?
    private var decodeFailed = false
    private var selected = false
    private var loadedEdge = 0
    private var progress: Double?
    private(set) var sourceURL: URL?
    private(set) var requestToken = UUID()
    var targetEdge: Int { selected ? 4096 : 2048 }
    var hasBitmap: Bool { image.image != nil }
    var zoomChanged: (() -> Void)?
    var retry: (() -> Void)?
    var advance: ((Int) -> Void)?
    var isMagnified: Bool { zoom.zoomScale > 1.01 || zoom.isZooming }
    var needsDecode: Bool { sourceURL != nil && loadedEdge != targetEdge && !decodeFailed && remoteError == nil }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        zoom.delegate = self
        zoom.minimumZoomScale = 1
        zoom.maximumZoomScale = 5
        zoom.bouncesZoom = true
        zoom.showsHorizontalScrollIndicator = false
        zoom.showsVerticalScrollIndicator = false
        zoom.scrollsToTop = false
        zoom.contentInsetAdjustmentBehavior = .never
        zoom.panGestureRecognizer.isEnabled = false
        image.contentMode = .scaleAspectFit
        image.isAccessibilityElement = true
        image.accessibilityTraits = [.image, .adjustable]
        image.advance = { [weak self] delta in self?.advance?(delta) }
        zoom.addSubview(image)
        addSubview(zoom)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        zoom.addGestureRecognizer(doubleTap)

        status.axis = .vertical
        status.alignment = .center
        status.spacing = 16
        spinner.color = .white
        spinner.hidesWhenStopped = true
        message.font = .preferredFont(forTextStyle: .subheadline)
        message.adjustsFontForContentSizeCategory = true
        message.textColor = .white
        message.numberOfLines = 4
        message.textAlignment = .center
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Reintentar"
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = UIColor.white.withAlphaComponent(0.16)
        configuration.background.cornerRadius = 12
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var attributes = incoming
            attributes.font = UIFont.preferredFont(forTextStyle: .headline)
            return attributes
        }
        retryButton.configuration = configuration
        retryButton.titleLabel?.adjustsFontForContentSizeCategory = true
        retryButton.addTarget(self, action: #selector(retryPressed), for: .touchUpInside)
        status.addArrangedSubview(ring)
        status.addArrangedSubview(spinner)
        status.addArrangedSubview(message)
        status.addArrangedSubview(retryButton)
        addSubview(status)
        status.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            status.centerXAnchor.constraint(equalTo: centerXAnchor),
            status.centerYAnchor.constraint(equalTo: centerYAnchor),
            status.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 28),
            status.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -28)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(item: MediaItem, url: URL?, progress: Double?, error: String?, selected: Bool) {
        name = item.name
        if self.selected && !selected { resetZoom() }
        self.selected = selected
        if sourceURL != url || (error != nil && remoteError == nil) {
            if representedID == item.id, sourceURL != nil, url != nil, error == nil, image.image != nil {
                // A better JPEG replaces the same photo. Keep its current
                // pixels until the serial decoder installs the new bitmap.
                loadedEdge = 0
            } else { clearImage() }
            sourceURL = url
            requestToken = UUID()
            decodeFailed = false
        }
        representedID = item.id
        self.remoteError = error
        self.progress = progress.map { min(1, max(0, $0.isFinite ? $0 : 0)) }
        accessibilityElementsHidden = !selected
        image.accessibilityLabel = name
        image.accessibilityHint = "Desliza hacia arriba o abajo para cambiar de foto."
        image.accessibilityValue = isMagnified ? "Ampliada" : "Tamaño original"
        retryButton.accessibilityIdentifier = selected ? "media.photo.retry" : nil
        status.accessibilityIdentifier = selected ? "media.photo.loading." + item.id : nil
        ring.accessibilityIdentifier = selected ? "media.photo.progress." + item.id : nil
        updateStatus()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        zoom.frame = bounds
        guard viewport != bounds.size else { return }
        fitImage()
    }

    func install(_ decoded: UIImage?, edge: Int) {
        if let decoded { image.image = decoded; loadedEdge = edge }
        decodeFailed = decoded == nil
        viewport = .zero
        setNeedsLayout()
        updateStatus()
    }

    func prepareRetry() {
        decodeFailed = false
        requestToken = UUID()
        updateStatus()
    }

    func releaseBitmap() {
        clearImage()
        decodeFailed = false
        updateStatus()
    }

    func resetZoom() {
        zoom.setZoomScale(1, animated: false)
        zoom.panGestureRecognizer.isEnabled = false
        image.accessibilityValue = "Tamaño original"
        centerImage()
        zoomChanged?()
    }

    func stop() {
        clearImage()
        sourceURL = nil
        requestToken = UUID()
        spinner.stopAnimating()
        status.isHidden = true
        image.advance = nil
        retry = nil
        advance = nil
        zoomChanged = nil
    }

    func removeAndStop() { stop(); removeFromSuperview() }

    private func clearImage() {
        resetZoom()
        image.image = nil
        loadedEdge = 0
        viewport = .zero
    }

    private func fitImage() {
        let scale = zoom.zoomScale
        zoom.setZoomScale(1, animated: false)
        viewport = bounds.size
        let size = image.image?.size ?? bounds.size
        let ratio = size.width > 0 && size.height > 0 ? min(bounds.width / size.width, bounds.height / size.height) : 1
        let fitted = CGSize(width: max(1, size.width * ratio), height: max(1, size.height * ratio))
        image.frame = CGRect(origin: .zero, size: fitted)
        zoom.contentSize = fitted
        if image.image != nil { zoom.setZoomScale(min(zoom.maximumZoomScale, max(1, scale)), animated: false) }
        zoom.panGestureRecognizer.isEnabled = isMagnified
        centerImage()
    }

    private func centerImage() {
        image.center = CGPoint(x: max(zoom.contentSize.width, zoom.bounds.width) / 2,
                               y: max(zoom.contentSize.height, zoom.bounds.height) / 2)
    }

    private func updateStatus() {
        image.isAccessibilityElement = image.image != nil
        image.accessibilityIdentifier = selected && image.image != nil ? "media.photo.document" : nil
        guard image.image == nil else { status.isHidden = true; spinner.stopAnimating(); return }
        status.isHidden = false
        let failure = remoteError ?? (decodeFailed ? "No se pudo mostrar esta imagen." : nil)
        retryButton.isHidden = failure == nil
        ring.isHidden = failure != nil || progress == nil
        if let progress { ring.progress = progress }
        if failure == nil && progress == nil { spinner.startAnimating() } else { spinner.stopAnimating() }
        message.text = failure ?? progress.map { "Cargando foto · \(Int(($0 * 100).rounded())) %" } ?? "Preparando foto…"
        message.accessibilityLabel = name + ". " + (message.text ?? "")
        status.accessibilityValue = progress.map { "\(Int(($0 * 100).rounded())) %" } ?? "Preparando"
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { image.image == nil ? nil : image }
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        zoom.panGestureRecognizer.isEnabled = true
        zoomChanged?()
    }
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
        zoom.panGestureRecognizer.isEnabled = isMagnified
        image.accessibilityValue = isMagnified ? "Ampliada" : "Tamaño original"
        zoomChanged?()
    }
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        zoom.panGestureRecognizer.isEnabled = scale > 1.01
        image.accessibilityValue = scale > 1.01 ? "Ampliada" : "Tamaño original"
        centerImage()
        zoomChanged?()
    }

    @objc private func doubleTap(_ gesture: UITapGestureRecognizer) {
        guard image.image != nil else { return }
        if zoom.zoomScale > 1.01 { zoom.setZoomScale(1, animated: true); return }
        let point = gesture.location(in: image)
        let scale: CGFloat = 3
        let target = CGRect(x: point.x - bounds.width / scale / 2, y: point.y - bounds.height / scale / 2,
                            width: bounds.width / scale, height: bounds.height / scale)
        zoom.zoom(to: target, animated: true)
    }

    @objc private func retryPressed() { retry?() }
}

private final class MediaPagerAccessibleImage: UIImageView {
    var advance: ((Int) -> Void)?
    override func accessibilityIncrement() { advance?(1) }
    override func accessibilityDecrement() { advance?(-1) }
}

private final class MediaPhotoProgressRing: UIView {
    private let track = CAShapeLayer()
    private let fill = CAShapeLayer()
    var progress: Double = 0 { didSet { fill.strokeEnd = CGFloat(min(1, max(0, progress))); accessibilityValue="\(Int((min(1,max(0,progress))*100).rounded())) %" } }
    override var intrinsicContentSize: CGSize { CGSize(width: 48, height: 48) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityLabel = "Carga de la foto"
        for shape in [track, fill] {
            shape.fillColor = UIColor.clear.cgColor
            shape.lineWidth = 3
            shape.lineCap = .round
            layer.addSublayer(shape)
        }
        track.strokeColor = UIColor.white.withAlphaComponent(0.22).cgColor
        fill.strokeColor = UIColor.white.cgColor
        fill.strokeEnd = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let radius = max(0, min(bounds.width, bounds.height) / 2 - 3)
        let path = UIBezierPath(arcCenter: CGPoint(x: bounds.midX, y: bounds.midY), radius: radius,
                                startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: true).cgPath
        track.frame = bounds
        fill.frame = bounds
        track.path = path
        fill.path = path
    }
}
#endif
