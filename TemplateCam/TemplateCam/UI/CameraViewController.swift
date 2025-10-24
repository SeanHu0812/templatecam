//
//  CameraViewController.swift
//  TemplateCam
//
//  Main camera view controller with template overlay and controls
//

import UIKit
import AVFoundation
import Vision

class CameraViewController: UIViewController {

    // MARK: - Properties

    private let captureSession = CaptureSession()
    private let photoPipeline = PhotoPipeline()
    private let overlayRenderer = OverlayRenderer()
    private let lensPicker = LensPicker()

    private var currentTemplate: Template
    private var poseRequest = VNDetectHumanBodyPoseRequest()
    private var lastPoseObservation: VNHumanBodyPoseObservation?
    private var lastSubjectHeight: CGFloat = 0

    private var frameCounter = 0
    private let frameInterval = 5  // Process every 5th frame

    // UI Components
    private var previewContainerView: UIView!
    private let coachingHUD = CoachingHUD()
    private var controlsView: TemplateControlsView!

    private let captureButton: UIButton = {
        let button = UIButton(type: .custom)
        button.backgroundColor = .white
        button.layer.cornerRadius = 37.5
        button.layer.borderWidth = 5
        button.layer.borderColor = UIColor.white.cgColor
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let importButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "photo.on.rectangle.angled"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        button.layer.cornerRadius = 25
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let lensButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("1x", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        button.layer.cornerRadius = 20
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let flashButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "bolt.slash.fill"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        button.layer.cornerRadius = 25
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private var flashMode: AVCaptureDevice.FlashMode = .off

    private let controlsToggleButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "slider.horizontal.3"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        button.layer.cornerRadius = 25
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    // MARK: - Initialization

    init(template: Template) {
        self.currentTemplate = template
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        self.currentTemplate = Template.defaultSeed()
        super.init(coder: coder)
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        checkCameraPermission()
        setupUI()
        setupActions()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        captureSession.startRunning()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession.stopRunning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        captureSession.videoPreviewLayer.frame = previewContainerView.bounds
    }

    // MARK: - Setup

    private func setupUI() {
        // Preview container
        previewContainerView = UIView()
        previewContainerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewContainerView)

        // Add preview layer
        captureSession.videoPreviewLayer.frame = view.bounds
        previewContainerView.layer.addSublayer(captureSession.videoPreviewLayer)

        // Setup overlay renderer
        overlayRenderer.setupLayers(on: previewContainerView)

        // Controls view
        controlsView = TemplateControlsView(
            tone: currentTemplate.cameraTargets.tone,
            whiteBalance: currentTemplate.cameraTargets.wb
        )
        controlsView.delegate = self
        controlsView.translatesAutoresizingMaskIntoConstraints = false
        controlsView.alpha = 0  // Initially hidden
        view.addSubview(controlsView)

        // Coaching HUD
        coachingHUD.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(coachingHUD)

        // Buttons
        view.addSubview(captureButton)
        view.addSubview(importButton)
        view.addSubview(lensButton)
        view.addSubview(flashButton)
        view.addSubview(controlsToggleButton)

        NSLayoutConstraint.activate([
            // Preview container
            previewContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            previewContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Coaching HUD
            coachingHUD.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            coachingHUD.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            coachingHUD.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -40),

            // Capture button
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            captureButton.widthAnchor.constraint(equalToConstant: 75),
            captureButton.heightAnchor.constraint(equalToConstant: 75),

            // Import button
            importButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            importButton.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            importButton.widthAnchor.constraint(equalToConstant: 50),
            importButton.heightAnchor.constraint(equalToConstant: 50),

            // Lens button
            lensButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            lensButton.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            lensButton.widthAnchor.constraint(equalToConstant: 50),
            lensButton.heightAnchor.constraint(equalToConstant: 40),

            // Flash button
            flashButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            flashButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            flashButton.widthAnchor.constraint(equalToConstant: 50),
            flashButton.heightAnchor.constraint(equalToConstant: 50),

            // Controls toggle
            controlsToggleButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            controlsToggleButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            controlsToggleButton.widthAnchor.constraint(equalToConstant: 50),
            controlsToggleButton.heightAnchor.constraint(equalToConstant: 50),

            // Controls view
            controlsView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            controlsView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            controlsView.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -20),
            controlsView.heightAnchor.constraint(equalToConstant: 300)
        ])
    }

    private func setupActions() {
        captureButton.addTarget(self, action: #selector(captureTapped), for: .touchUpInside)
        importButton.addTarget(self, action: #selector(importTapped), for: .touchUpInside)
        lensButton.addTarget(self, action: #selector(lensTapped), for: .touchUpInside)
        flashButton.addTarget(self, action: #selector(flashTapped), for: .touchUpInside)
        controlsToggleButton.addTarget(self, action: #selector(controlsToggleTapped), for: .touchUpInside)
    }

    // MARK: - Camera Permission

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.setupCamera()
                    }
                }
            }
        case .denied, .restricted:
            showPermissionAlert()
        @unknown default:
            break
        }
    }

    private func showPermissionAlert() {
        let alert = UIAlertController(
            title: "Camera Access Required",
            message: "Please enable camera access in Settings",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - Setup Camera

    private func setupCamera() {
        captureSession.configureSession(videoFrameDelegate: self)
        captureSession.startRunning()

        // Apply template settings
        if let device = captureSession.currentDevice {
            ExposureWB.apply(template: currentTemplate, to: device)
        }
    }

    // MARK: - Actions

    @objc private func captureTapped() {
        Haptics.shared.triggerHeavy()

        captureSession.capturePhoto(flashMode: flashMode) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let image):
                // Apply tone adjustments
                guard let ciImage = CIImage(image: image) else { return }
                let processedImage = self.photoPipeline.applyPhoto(ciImage, tone: self.currentTemplate.cameraTargets.tone)

                if let finalImage = self.photoPipeline.renderToUIImage(processedImage) {
                    self.savePhoto(finalImage)
                }

            case .failure(let error):
                Logger.logError(error, context: "Photo capture")
            }
        }
    }

    @objc private func importTapped() {
        let importVC = ImportTemplateViewController()
        importVC.delegate = self
        let navController = UINavigationController(rootViewController: importVC)
        present(navController, animated: true)
    }

    @objc private func lensTapped() {
        // Cycle through available lenses
        guard let currentLens = captureSession.currentLens else { return }

        let currentIndex = captureSession.availableLenses.firstIndex { $0.device == currentLens.device } ?? 0
        let nextIndex = (currentIndex + 1) % captureSession.availableLenses.count
        let nextLens = captureSession.availableLenses[nextIndex]

        captureSession.switchLens(to: nextLens, videoFrameDelegate: self)
        lensButton.setTitle(lensName(for: nextLens), for: .normal)

        Haptics.shared.triggerMedium()
    }

    @objc private func flashTapped() {
        // Cycle through flash modes
        switch flashMode {
        case .off:
            flashMode = .auto
            flashButton.setImage(UIImage(systemName: "bolt.badge.automatic"), for: .normal)
        case .auto:
            flashMode = .on
            flashButton.setImage(UIImage(systemName: "bolt.fill"), for: .normal)
        case .on:
            flashMode = .off
            flashButton.setImage(UIImage(systemName: "bolt.slash.fill"), for: .normal)
        @unknown default:
            flashMode = .off
        }

        Haptics.shared.triggerSelection()
    }

    @objc private func controlsToggleTapped() {
        UIView.animate(withDuration: 0.3) {
            self.controlsView.alpha = self.controlsView.alpha > 0 ? 0 : 1
        }
        Haptics.shared.triggerSelection()
    }

    // MARK: - Helpers

    private func lensName(for lens: LensOption) -> String {
        switch lens.kind {
        case .ultrawide: return "0.5x"
        case .wide: return "1x"
        case .tele: return "2x"
        }
    }

    private func savePhoto(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(imageSaved(_:didFinishSavingWithError:contextInfo:)), nil)
    }

    @objc private func imageSaved(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if let error = error {
            Logger.logError(error, context: "Save photo")
        } else {
            Logger.log("Photo saved successfully")
            Haptics.shared.triggerSuccess()
        }
    }

    func updateTemplate(_ template: Template) {
        self.currentTemplate = template
        controlsView.updateTemplate(tone: template.cameraTargets.tone, whiteBalance: template.cameraTargets.wb)

        // Apply settings to camera
        if let device = captureSession.currentDevice {
            ExposureWB.apply(template: template, to: device)
        }

        lensPicker.reset()
        Haptics.shared.resetCooldown()
        coachingHUD.resetHaptic()
    }
}

// MARK: - Video Frame Delegate

extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCounter += 1
        guard frameCounter % frameInterval == 0 else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Run Vision pose detection
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([poseRequest])

            guard let observation = poseRequest.results?.first else { return }

            // Get subject bounding box
            let bbox = observation.boundingBox
            let subjectHeight = bbox.size.height

            DispatchQueue.main.async {
                self.lastPoseObservation = observation
                self.lastSubjectHeight = subjectHeight

                // Update overlays
                self.overlayRenderer.updateOverlays(
                    template: self.currentTemplate,
                    poseObservation: observation,
                    viewBounds: self.previewContainerView.bounds,
                    previewLayer: self.captureSession.videoPreviewLayer
                )

                // Score match
                let matchResult = MatchScorer.scoreMatch(
                    liveSubjectHeight: subjectHeight,
                    targetHeight: self.currentTemplate.subject.targetBoxHeightPct,
                    livePose: observation,
                    templateKeybones: self.currentTemplate.subject.keybones
                )

                // Update coaching HUD
                self.coachingHUD.update(with: matchResult)

                // Check if lens needs adjustment
                if self.lensPicker.shouldReevaluate(currentHeight: subjectHeight, targetHeight: self.currentTemplate.subject.targetBoxHeightPct) {
                    self.evaluateLensSelection()
                }
            }

        } catch {
            Logger.logError(error, context: "Vision pose detection")
        }
    }

    private func evaluateLensSelection() {
        // Build probes for each lens
        var probes: [LensProbe] = []

        for lens in captureSession.availableLenses {
            // Use current measurement or estimate
            let probe = LensProbe(lens: lens, subjectHeightLive: lastSubjectHeight)
            probes.append(probe)
        }

        // Pick best lens
        if let (selectedLens, zoomNeeded) = lensPicker.pickLens(targetHeight: currentTemplate.subject.targetBoxHeightPct, probes: probes) {
            if selectedLens.device != captureSession.currentLens?.device {
                // Switch lens
                overlayRenderer.fadeOut()
                captureSession.switchLens(to: selectedLens, videoFrameDelegate: self)
                captureSession.setZoom(zoomNeeded)
                lensButton.setTitle(lensName(for: selectedLens), for: .normal)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.overlayRenderer.fadeIn()
                }
            } else {
                // Just adjust zoom
                captureSession.setZoom(zoomNeeded)
            }
        }
    }
}

// MARK: - Template Controls Delegate

extension CameraViewController: TemplateControlsDelegate {

    func controlsDidUpdate(tone: Template.CameraTargets.Tone, wb: Template.CameraTargets.WhiteBalance) {
        // Update current template
        currentTemplate.cameraTargets.tone = tone
        currentTemplate.cameraTargets.wb = wb

        // Apply to camera
        if let device = captureSession.currentDevice {
            ExposureWB.setExposureBias(currentTemplate.cameraTargets.exposureBiasEV, to: device)
            ExposureWB.lockWhiteBalance(temperature: wb.temperature, tint: wb.tint, device: device)
        }

        Logger.log("Controls updated: tone and WB applied")
    }
}

// MARK: - Import Template Delegate

extension CameraViewController: ImportTemplateDelegate {

    func didImportTemplate(_ template: Template) {
        updateTemplate(template)
        Logger.log("New template imported: \(template.id)")
    }
}
