#if os(iOS) && DEBUG
import AVFoundation
import UIKit
import Vision

/// The turn between two frontal readings is a basic cooperation check, not certified liveness.
struct AttendanceFaceTurn {
    enum Step { case front, turn, back }
    private(set) var step = Step.front
    private var first: AttendanceFaceSignature?
    private var started: TimeInterval = 0

    mutating func observe(yaw: Double, at time: TimeInterval, signature: () -> AttendanceFaceSignature?) -> AttendanceFaceSignature? {
        if step != .front && time - started > 9 { self = Self() }
        switch step {
        case .front:
            if abs(yaw) < 0.15, let sample = signature() {
                first = sample
                started = time
                step = .turn
            }
        case .turn:
            if abs(yaw) > 0.24 && time - started >= 0.25 { step = .back }
        case .back:
            if abs(yaw) < 0.15, let sample = signature() {
                let consistent = first?.resembles(sample) == true
                self = Self()
                return consistent ? sample : nil
            }
        }
        return nil
    }
}

private final class AttendanceFaceStream: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "co.jacmusic.asistencia.camara")
    private let output = AVCaptureVideoDataOutput()
    private var orientation = AVCaptureVideoOrientation.portrait
    private var turn = AttendanceFaceTurn()
    private var finished = false
    private var lastFrame: TimeInterval = 0
    private var lastInstruction = ""
    let event: (Result<AttendanceFaceSignature, Error>) -> Void
    let instruction: (String) -> Void

    init(event: @escaping (Result<AttendanceFaceSignature, Error>) -> Void, instruction: @escaping (String) -> Void) {
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
            turn = AttendanceFaceTurn()
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
    private func end(_ result: Result<AttendanceFaceSignature, Error>) {
        guard !finished else { return }
        finished = true
        DispatchQueue.main.async { self.event(result) }
    }
    private func guide(_ message: String) {
        guard lastInstruction != message else { return }
        lastInstruction = message
        DispatchQueue.main.async { self.instruction(message) }
    }
    private func headTurn(of face: VNFaceObservation) -> Double? {
        let measured = face.yaw?.doubleValue
        if let measured, abs(measured) >= 0.15 { return measured }
        // Some Vision revisions give a frontal bin or nil on modest turns. The nose moves
        // sideways relative to the midpoint of the eyes as the participant turns.
        func centerX(_ region: VNFaceLandmarkRegion2D?) -> Double? {
            guard let region, region.pointCount > 0 else { return nil }
            return region.normalizedPoints.reduce(0) { $0 + Double($1.x) } / Double(region.pointCount)
        }
        guard let marks = face.landmarks, let left = centerX(marks.leftEye), let right = centerX(marks.rightEye),
              let nose = centerX(marks.nose), abs(right - left) > 0.1 else { return measured }
        let offset = atan(2 * (nose - (left + right) / 2) / abs(right - left))
        return measured == nil || abs(offset) > 0.28 ? offset : measured
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard !finished, now - lastFrame > 0.12, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        if now - lastFrame > 1.2 { turn = AttendanceFaceTurn() }
        lastFrame = now
        let request = VNDetectFaceLandmarksRequest()
        do { try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:]).perform([request]) }
        catch { turn = AttendanceFaceTurn(); guide("Busca buena luz y mira a la cámara."); return }
        let faces = request.results ?? []
        guard faces.count == 1, let face = faces.first, face.boundingBox.width >= 0.18, let yaw = headTurn(of: face) else {
            turn = AttendanceFaceTurn()
            guide(faces.count > 1 ? "Debe aparecer una sola persona." : "Acércate y mira de frente con buena luz.")
            return
        }
        if let signature = turn.observe(yaw: yaw, at: now, signature: { AttendanceFaceSignature.capture(face, in: buffer) }) {
            end(.success(signature))
            return
        }
        switch turn.step {
        case .front: guide("Mira de frente con buena luz.")
        case .turn: guide("Gira un poco la cabeza hacia un lado.")
        case .back: guide("Vuelve a mirar de frente.")
        }
    }
}

@MainActor
final class AttendanceFaceCamera: UIViewController {
    private var completion: ((Result<AttendanceFaceSignature, Error>) -> Void)?
    private var timeout: Timer?
    private let hint = UILabel()
    private let titleLabel = UILabel()
    private lazy var stream = AttendanceFaceStream(event: { [weak self] result in self?.finish(result) },
                                                  instruction: { [weak self] text in self?.hint.text = text })
    private lazy var preview = AVCaptureVideoPreviewLayer(session: stream.session)

    static var frontCamera: AVCaptureDevice? { AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) }

    static func collect(for name: String, from presenter: UIViewController, stillAllowed: () -> Bool) async throws -> AttendanceFaceSignature {
        guard let camera = frontCamera else { throw APIError.message("Para comparar un rostro, usa un dispositivo con cámara frontal. Puedes elegir supervisión.") }
        guard await AVCaptureDevice.requestAccess(for: .video) else { throw APIError.message("Para usar la comparación habilita Cámara en Ajustes de JAC. También puedes elegir supervisión.") }
        guard stillAllowed(), presenter.viewIfLoaded?.window?.windowScene?.activationState == .foregroundActive,
              presenter.presentedViewController == nil else { throw APIError.message("Vuelve al kiosco e intenta de nuevo.") }
        return try await withCheckedThrowingContinuation { continuation in
            let screen = AttendanceFaceCamera()
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
        hint.text = "Mira de frente."
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
    private func finish(_ result: Result<AttendanceFaceSignature, Error>) {
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
