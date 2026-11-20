#if os(iOS)
import AVFoundation
import UIKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Three compatible frontal readings protect against a single blurry frame or a change of subject.
struct AttendanceFrontalCapture {
    private var samples: [AttendanceFaceSignature] = []
    private var lastSample: TimeInterval?
    var isReading: Bool { !samples.isEmpty }

    mutating func observe(yaw: Double?, at time: TimeInterval, signature: () -> AttendanceFaceSignature?) -> AttendanceFaceSignature? {
        if let lastSample {
            if time - lastSample > 1 { self = Self() }
            else if time - lastSample < 0.18 { return nil }
        }
        guard yaw.map({ abs($0) <= 0.35 }) ?? true, let sample = signature() else {
            self = Self()
            return nil
        }
        if let first = samples.first, !first.resembles(sample) { samples.removeAll() }
        samples.append(sample)
        lastSample = time
        guard samples.count == 3 else { return nil }
        let result = AttendanceFaceSignature.mean(of: samples)
        self = Self()
        return result
    }
}

struct AttendanceFaceReading {
    let signature: AttendanceFaceSignature
    let photo: Data?

    static func portrait(bounds: CGRect, image: CIImage, context: CIContext) -> Data? {
        let box = VNImageRectForNormalizedRect(bounds, Int(image.extent.width), Int(image.extent.height))
        let crop = box.insetBy(dx: -box.width * 0.12, dy: -box.height * 0.15).integral.intersection(image.extent)
        guard !crop.isEmpty else { return nil }
        let scale = min(1, 360 / max(crop.width, crop.height))
        let cut = image.cropped(to: crop)
            .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let size = CGRect(x: 0, y: 0, width: floor(crop.width * scale), height: floor(crop.height * scale))
        guard let pixels = context.createCGImage(cut, from: size) else { return nil }
        let bytes = NSMutableData()
        guard let writer = CGImageDestinationCreateWithData(bytes as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(writer, pixels, [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary)
        guard CGImageDestinationFinalize(writer), bytes.length <= 96 * 1024 else { return nil }
        return bytes as Data
    }
}

private final class AttendanceFaceStream: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "co.jacmusic.asistencia.camara")
    private let output = AVCaptureVideoDataOutput()
    private var orientation = AVCaptureVideoOrientation.portrait
    private var frontal = AttendanceFrontalCapture()
    private let photoContext = CIContext(options: [.cacheIntermediates: false])
    private let includePhoto: Bool
    private var finished = false
    private var lastFrame: TimeInterval = 0
    private var lastInstruction = ""
    let event: (Result<AttendanceFaceReading, Error>) -> Void
    let instruction: (String) -> Void

    init(includePhoto: Bool, event: @escaping (Result<AttendanceFaceReading, Error>) -> Void, instruction: @escaping (String) -> Void) {
        self.includePhoto = includePhoto
        self.event = event
        self.instruction = instruction
    }

    func start(camera: AVCaptureDevice) {
        queue.async { [self] in
            guard !finished else { return }
            session.beginConfiguration()
            do {
                let input = try AVCaptureDeviceInput(device: camera)
                guard session.canAddInput(input), session.canAddOutput(output) else {
                    throw APIError.message("La cámara frontal está ocupada. Puedes usar la supervisión.")
                }
                session.addInput(input)
                if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(self, queue: queue)
                session.addOutput(output)
                orientOutput()
                session.commitConfiguration()
                session.startRunning()
            } catch {
                session.commitConfiguration()
                end(.failure(error))
            }
        }
    }

    func rotate(_ value: AVCaptureVideoOrientation) {
        queue.async { [self] in
            guard value != orientation else { return }
            orientation = value
            frontal = AttendanceFrontalCapture()
            orientOutput()
        }
    }
    private func orientOutput() {
        if let connection = output.connection(with: .video) {
            if connection.isVideoOrientationSupported { connection.videoOrientation = orientation }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }
    }
    func stop() {
        queue.async { [self] in
            finished = true
            output.setSampleBufferDelegate(nil, queue: nil)
            if session.isRunning { session.stopRunning() }
        }
    }
    private func end(_ result: Result<AttendanceFaceReading, Error>) {
        guard !finished else { return }
        finished = true
        DispatchQueue.main.async { self.event(result) }
    }
    private func guide(_ message: String) {
        guard lastInstruction != message else { return }
        lastInstruction = message
        DispatchQueue.main.async { self.instruction(message) }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard !finished, now - lastFrame > 0.12, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        if now - lastFrame > 1.2 { frontal = AttendanceFrontalCapture() }
        lastFrame = now
        let request = VNDetectFaceLandmarksRequest()
        do { try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:]).perform([request]) }
        catch { frontal = AttendanceFrontalCapture(); guide("Busca buena luz y mira a la cámara."); return }
        let faces = request.results ?? []
        guard faces.count == 1, let face = faces.first, face.boundingBox.width >= 0.16 else {
            frontal = AttendanceFrontalCapture()
            guide(faces.count > 1 ? "Debe aparecer una sola persona." : "Acércate y mira de frente con buena luz.")
            return
        }
        if let signature = frontal.observe(yaw: face.yaw?.doubleValue, at: now, signature: { AttendanceFaceSignature.capture(face, in: buffer) }) {
            let photo = includePhoto ? AttendanceFaceReading.portrait(bounds: face.boundingBox, image: CIImage(cvPixelBuffer: buffer), context: photoContext) : nil
            if includePhoto && photo == nil { guide("Mira a la cámara un instante más para tomar la foto."); return }
            end(.success(AttendanceFaceReading(signature: signature, photo: photo)))
            return
        }
        guide(frontal.isReading ? "Quédate así un instante." : "Mira a la cámara con buena luz.")
    }
}

@MainActor
final class AttendanceFaceCamera: UIViewController {
    private var completion: ((Result<AttendanceFaceReading, Error>) -> Void)?
    private var timeout: Timer?
    private let hint = UILabel()
    private let titleLabel = UILabel()
    private var includePhoto = false
    private lazy var stream = AttendanceFaceStream(includePhoto: includePhoto, event: { [weak self] result in self?.finish(result) },
                                                  instruction: { [weak self] text in
        self?.hint.text = text
        // The preview connection can appear after the first layout on a landscape iPad.
        self?.view.setNeedsLayout()
        if UIAccessibility.isVoiceOverRunning { UIAccessibility.post(notification: .announcement, argument: text) }
    })
    private lazy var preview = AVCaptureVideoPreviewLayer(session: stream.session)

    static var frontCamera: AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTrueDepthCamera]
        return AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .front).devices.first
    }

    static func collect(for name: String, from presenter: UIViewController, includePhoto: Bool = false, stillAllowed: () -> Bool) async throws -> AttendanceFaceReading {
        guard let camera = frontCamera else { throw APIError.message("Para comparar un rostro, usa un dispositivo con cámara frontal. Puedes elegir supervisión.") }
        guard await AVCaptureDevice.requestAccess(for: .video) else { throw APIError.message("Para usar la comparación habilita Cámara en Ajustes de JAC. También puedes elegir supervisión.") }
        guard stillAllowed(), let scene = presenter.viewIfLoaded?.window?.windowScene,
              [.foregroundActive, .foregroundInactive].contains(scene.activationState), presenter.presentedViewController == nil else { throw APIError.message("Vuelve al kiosco e intenta de nuevo.") }
        return try await withCheckedThrowingContinuation { continuation in
            let screen = AttendanceFaceCamera()
            screen.includePhoto = includePhoto
            screen.modalPresentationStyle = .overFullScreen
            screen.titleLabel.text = name
            screen.completion = { continuation.resume(with: $0) }
            presenter.present(screen, animated: true) {
                guard screen.completion != nil else { return }
                screen.stream.start(camera: camera)
                screen.timeout = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak screen] _ in
                    Task { @MainActor in screen?.finish(.failure(APIError.message("La lectura terminó sin una muestra clara. Puedes reintentar o elegir supervisión."))) }
                }
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        preview.videoGravity = .resizeAspect
        view.layer.addSublayer(preview)
        let panel = UIStackView()
        panel.axis = .vertical
        panel.spacing = 8
        panel.alignment = .center
        panel.isLayoutMarginsRelativeArrangement = true
        panel.directionalLayoutMargins = .init(top: 12, leading: 16, bottom: 12, trailing: 16)
        panel.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        panel.layer.cornerRadius = 12
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)
        for label in [titleLabel, hint] {
            label.textColor = .white
            label.textAlignment = .center
            label.numberOfLines = 0
            label.font = .preferredFont(forTextStyle: label === hint ? .title3 : .subheadline)
            label.adjustsFontForContentSizeCategory = true
            panel.addArrangedSubview(label)
        }
        hint.text = includePhoto ? "Mira de frente. Se guardará una foto con tu marcación." : "Mira de frente."
        let cancel = UIButton(type: .system)
        cancel.setTitle("Cancelar", for: .normal)
        cancel.tintColor = .white
        cancel.addTarget(self, action: #selector(cancelCapture), for: .touchUpInside)
        panel.addArrangedSubview(cancel)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            panel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            panel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            cancel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(cancelCapture), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview.frame = view.bounds
        guard let ui = view.window?.windowScene?.interfaceOrientation,
              let direction = AVCaptureVideoOrientation(rawValue: ui.rawValue) else { return }
        if let connection = preview.connection, connection.isVideoOrientationSupported { connection.videoOrientation = direction }
        stream.rotate(direction)
    }
    @objc func cancelCapture() { finish(.failure(APIError.message("Captura cancelada."))) }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if completion != nil { cancelCapture() }
    }
    private func finish(_ result: Result<AttendanceFaceReading, Error>) {
        guard let callback = completion else { return }
        completion = nil
        timeout?.invalidate()
        stream.stop()
        NotificationCenter.default.removeObserver(self)
        if presentingViewController == nil || isBeingDismissed { callback(result) }
        else { dismiss(animated: true) { callback(result) } }
    }
}
#endif
