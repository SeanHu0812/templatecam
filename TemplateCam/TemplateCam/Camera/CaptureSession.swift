//
//  CaptureSession.swift
//  TemplateCam
//
//  AVFoundation camera session management with multi-lens support
//

import AVFoundation
import UIKit

// MARK: - Lens Option

struct LensOption {
    let device: AVCaptureDevice
    let kind: LensKind
    let maxZoom: CGFloat

    enum LensKind: String {
        case ultrawide
        case wide
        case tele

        var displayName: String {
            switch self {
            case .ultrawide: return "Ultra Wide"
            case .wide: return "Wide"
            case .tele: return "Telephoto"
            }
        }
    }
}

// MARK: - Capture Session

class CaptureSession: NSObject {

    // MARK: - Properties

    let session = AVCaptureSession()
    private(set) var videoPreviewLayer: AVCaptureVideoPreviewLayer!

    private let sessionQueue = DispatchQueue(label: "com.templatecam.captureSession")
    private var photoOutput = AVCapturePhotoOutput()
    private var videoDataOutput = AVCaptureVideoDataOutput()

    private(set) var currentDevice: AVCaptureDevice?
    private var currentInput: AVCaptureDeviceInput?

    private(set) var availableLenses: [LensOption] = []
    private(set) var currentLens: LensOption?

    var photoCaptureCompletion: ((Result<UIImage, Error>) -> Void)?
    var videoFrameHandler: ((CMSampleBuffer) -> Void)?

    // MARK: - Initialization

    override init() {
        super.init()
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: session)
        videoPreviewLayer.videoGravity = .resizeAspectFill
        enumerateLenses()
    }

    // MARK: - Lens Enumeration

    private func enumerateLenses() {
        var lenses: [LensOption] = []

        // Enumerate all back camera devices
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInUltraWideCamera,
            .builtInWideAngleCamera,
            .builtInTelephotoCamera
        ]

        for deviceType in deviceTypes {
            if let device = AVCaptureDevice.default(deviceType, for: .video, position: .back) {
                let kind: LensOption.LensKind
                switch deviceType {
                case .builtInUltraWideCamera:
                    kind = .ultrawide
                case .builtInTelephotoCamera:
                    kind = .tele
                default:
                    kind = .wide
                }

                let lens = LensOption(
                    device: device,
                    kind: kind,
                    maxZoom: device.activeFormat.videoMaxZoomFactor
                )
                lenses.append(lens)
                Logger.log("Lens available: \(kind.displayName) (maxZoom: \(String(format: "%.1fx", lens.maxZoom)))")
            }
        }

        // Sort: wide, ultrawide, tele
        lenses.sort { lhs, rhs in
            let order: [LensOption.LensKind] = [.wide, .ultrawide, .tele]
            guard let lhsIndex = order.firstIndex(of: lhs.kind),
                  let rhsIndex = order.firstIndex(of: rhs.kind) else {
                return false
            }
            return lhsIndex < rhsIndex
        }

        availableLenses = lenses
    }

    // MARK: - Session Control

    func startRunning() {
        sessionQueue.async {
            if !self.session.isRunning {
                self.session.startRunning()
                Logger.log("Capture session started")
            }
        }
    }

    func stopRunning() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
                Logger.log("Capture session stopped")
            }
        }
    }

    // MARK: - Configure Session

    func configureSession(lens: LensOption? = nil, videoFrameDelegate: AVCaptureVideoDataOutputSampleBufferDelegate? = nil) {
        sessionQueue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            // Select lens (default to wide)
            let targetLens = lens ?? self.availableLenses.first(where: { $0.kind == .wide }) ?? self.availableLenses.first
            guard let selectedLens = targetLens else {
                Logger.log("No camera available")
                self.session.commitConfiguration()
                return
            }

            // Remove old input
            if let oldInput = self.currentInput {
                self.session.removeInput(oldInput)
            }

            // Add new input
            do {
                let input = try AVCaptureDeviceInput(device: selectedLens.device)
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.currentInput = input
                    self.currentDevice = selectedLens.device
                    self.currentLens = selectedLens
                    Logger.log("Switched to \(selectedLens.kind.displayName)")
                }
            } catch {
                Logger.logError(error, context: "Failed to create device input")
                self.session.commitConfiguration()
                return
            }

            // Add photo output
            if !self.session.outputs.contains(self.photoOutput) {
                if self.session.canAddOutput(self.photoOutput) {
                    self.session.addOutput(self.photoOutput)
                    self.photoOutput.isHighResolutionCaptureEnabled = true
                    self.photoOutput.maxPhotoQualityPrioritization = .quality
                }
            }

            // Add video output for frame analysis
            if !self.session.outputs.contains(self.videoDataOutput) {
                self.videoDataOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                self.videoDataOutput.alwaysDiscardsLateVideoFrames = true

                if self.session.canAddOutput(self.videoDataOutput) {
                    self.session.addOutput(self.videoDataOutput)
                    if let delegate = videoFrameDelegate {
                        self.videoDataOutput.setSampleBufferDelegate(delegate, queue: DispatchQueue(label: "com.templatecam.videoFrames"))
                    }
                }
            }

            self.session.commitConfiguration()
        }
    }

    // MARK: - Switch Lens

    func switchLens(to lens: LensOption, videoFrameDelegate: AVCaptureVideoDataOutputSampleBufferDelegate? = nil) {
        sessionQueue.async {
            self.session.beginConfiguration()

            // Remove old input
            if let oldInput = self.currentInput {
                self.session.removeInput(oldInput)
            }

            // Add new input
            do {
                let input = try AVCaptureDeviceInput(device: lens.device)
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.currentInput = input
                    self.currentDevice = lens.device
                    self.currentLens = lens
                    Logger.logLensSwitch(from: self.currentLens?.kind.rawValue ?? "none", to: lens.kind.rawValue, zoom: 1.0)
                }
            } catch {
                Logger.logError(error, context: "Failed to switch lens")
            }

            // Update video output delegate if needed
            if let delegate = videoFrameDelegate {
                self.videoDataOutput.setSampleBufferDelegate(delegate, queue: DispatchQueue(label: "com.templatecam.videoFrames"))
            }

            self.session.commitConfiguration()
        }
    }

    // MARK: - Zoom

    func setZoom(_ factor: CGFloat) {
        guard let device = currentDevice else { return }

        sessionQueue.async {
            do {
                try device.lockForConfiguration()

                let clampedZoom = max(1.0, min(factor, device.activeFormat.videoMaxZoomFactor))
                device.videoZoomFactor = clampedZoom

                device.unlockForConfiguration()

                Logger.logZoom(clampedZoom, lens: self.currentLens?.kind.rawValue ?? "unknown")
            } catch {
                Logger.logError(error, context: "Failed to set zoom")
            }
        }
    }

    // MARK: - Exposure

    func setExposureBias(_ bias: Float) {
        guard let device = currentDevice else { return }

        sessionQueue.async {
            do {
                try device.lockForConfiguration()

                let clampedBias = max(device.minExposureTargetBias, min(bias, device.maxExposureTargetBias))
                device.setExposureTargetBias(clampedBias)

                device.unlockForConfiguration()
            } catch {
                Logger.logError(error, context: "Failed to set exposure bias")
            }
        }
    }

    func setExposurePoint(_ point: CGPoint) {
        guard let device = currentDevice,
              device.isExposurePointOfInterestSupported else { return }

        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                device.exposurePointOfInterest = point
                device.exposureMode = .continuousAutoExposure
                device.unlockForConfiguration()
            } catch {
                Logger.logError(error, context: "Failed to set exposure point")
            }
        }
    }

    func lockExposureIfNeeded() {
        guard let device = currentDevice else { return }

        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                if device.exposureMode == .continuousAutoExposure {
                    device.exposureMode = .locked
                }
                device.unlockForConfiguration()
            } catch {
                Logger.logError(error, context: "Failed to lock exposure")
            }
        }
    }

    // MARK: - White Balance

    func lockWhiteBalance(temperature: CGFloat, tint: CGFloat) {
        guard let device = currentDevice else { return }

        sessionQueue.async {
            do {
                try device.lockForConfiguration()

                if device.isWhiteBalanceModeSupported(.locked) {
                    let tempTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                        temperature: Float(temperature),
                        tint: Float(tint)
                    )

                    var gains = device.deviceWhiteBalanceGains(for: tempTint)

                    // Clamp gains
                    let maxGain = device.maxWhiteBalanceGain
                    gains.redGain = max(1.0, min(gains.redGain, maxGain))
                    gains.greenGain = max(1.0, min(gains.greenGain, maxGain))
                    gains.blueGain = max(1.0, min(gains.blueGain, maxGain))

                    device.setWhiteBalanceModeLocked(with: gains)
                    Logger.logExposureLock(ev: 0, temperature: temperature, tint: tint)
                }

                device.unlockForConfiguration()
            } catch {
                Logger.logError(error, context: "Failed to lock white balance")
            }
        }
    }

    // MARK: - Capture Photo

    func capturePhoto(flashMode: AVCaptureDevice.FlashMode = .off, completion: @escaping (Result<UIImage, Error>) -> Void) {
        sessionQueue.async {
            self.photoCaptureCompletion = completion

            let settings = AVCapturePhotoSettings()
            settings.flashMode = flashMode
            settings.isHighResolutionPhotoEnabled = true
            settings.photoQualityPrioritization = .quality

            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
}

// MARK: - Photo Capture Delegate

extension CaptureSession: AVCapturePhotoCaptureDelegate {

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            photoCaptureCompletion?(.failure(error))
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            photoCaptureCompletion?(.failure(NSError(domain: "CaptureSession", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create image from photo data"])))
            return
        }

        photoCaptureCompletion?(.success(image))
    }
}
