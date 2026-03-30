import SwiftUI
import AVFoundation

struct QRScannerView: UIViewControllerRepresentable {
    let onScanned: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let vc = QRScannerViewController()
        vc.coordinator = context.coordinator
        context.coordinator.controller = vc
        vc.onScanned = onScanned
        return vc
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {
        uiViewController.onScanned = onScanned
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        weak var controller: QRScannerViewController?

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard
                let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                object.type == .qr,
                let value = object.stringValue
            else { return }
            controller?.handleScannedCode(value)
        }
    }
}

final class QRScannerViewController: UIViewController {
    var coordinator: QRScannerView.Coordinator?
    var onScanned: ((String) -> Void)?

    private let sessionQueue = DispatchQueue(label: "com.tunehaven.scanner")
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didCommitConfiguration = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.insertSublayer(preview, at: 0)
        previewLayer = preview

        let overlay = ScanOverlayView(frame: view.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.isUserInteractionEnabled = false
        view.addSubview(overlay)

        sessionQueue.async { [weak self] in
            self?.prepareSession()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startCaptureIfNeeded()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func handleScannedCode(_ value: String) {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async { [weak self] in
                self?.onScanned?(value)
            }
        }
    }

    private func prepareSession() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.sessionQueue.async {
                        self?.configureSession()
                    }
                } else {
                    DispatchQueue.main.async { [weak self] in
                        self?.showPermissionDeniedUI()
                    }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async { [weak self] in
                self?.showPermissionDeniedUI()
            }
        @unknown default:
            break
        }
    }

    private func showPermissionDeniedUI() {
        let label = UILabel()
        label.text = "需要相机权限才能扫描二维码\n请在「设置」中允许访问相机"
        label.textColor = .white
        label.font = .systemFont(ofSize: 15)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        let button = UIButton(type: .system)
        button.setTitle("前往设置", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.setTitleColor(.systemBlue, for: .normal)
        button.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 16),
        ])
    }

    @objc private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func configureSession() {
        guard !didCommitConfiguration else { return }
        guard let device = AVCaptureDevice.default(for: .video) else { return }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            let output = AVCaptureMetadataOutput()

            session.beginConfiguration()
            defer { session.commitConfiguration() }

            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                return
            }

            if session.canAddOutput(output) {
                session.addOutput(output)
            } else {
                session.removeInput(input)
                return
            }

            output.setMetadataObjectsDelegate(coordinator, queue: sessionQueue)
            output.metadataObjectTypes = [.qr]
            didCommitConfiguration = true
        } catch {
            return
        }

        startCaptureIfNeeded()
    }

    private func startCaptureIfNeeded() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.viewIfLoaded?.window != nil else { return }
            self.sessionQueue.async { [weak self] in
                guard let self, self.didCommitConfiguration else { return }
                guard !self.session.isRunning else { return }
                self.session.startRunning()
            }
        }
    }
}

private final class ScanOverlayView: UIView {
    private let dimFill = CAShapeLayer()
    private let frameStroke = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        dimFill.fillRule = .evenOdd
        dimFill.fillColor = UIColor.black.withAlphaComponent(0.5).cgColor
        layer.addSublayer(dimFill)
        frameStroke.fillColor = UIColor.clear.cgColor
        frameStroke.strokeColor = UIColor.white.withAlphaComponent(0.85).cgColor
        frameStroke.lineWidth = 2
        layer.addSublayer(frameStroke)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds
        let side = min(b.width, b.height) * 0.68
        let hole = CGRect(
            x: (b.width - side) / 2,
            y: (b.height - side) / 2,
            width: side,
            height: side
        )

        let path = UIBezierPath(rect: b)
        path.append(UIBezierPath(roundedRect: hole, cornerRadius: 12))
        dimFill.path = path.cgPath
        dimFill.frame = b

        frameStroke.path = UIBezierPath(roundedRect: hole, cornerRadius: 12).cgPath
        frameStroke.frame = b
    }
}
