import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif
import AVFoundation
import Photos
import CoreImage
import CoreImage.CIFilterBuiltins

@main
struct TemplateCamApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

// MARK: - Models
struct OverlayElement: Identifiable, Codable {
    enum Kind: String, Codable { case line, rect, ellipse, path, grid }
    var id: UUID = UUID()
    var kind: Kind
    // normalized coordinates [0,1] in preview space
    var points: [CGPoint] = [] // for line/path (interpreted as sequence)
    var rect: CGRect = .zero   // for rect/ellipse
    var gridRows: Int = 0      // for grid
    var gridCols: Int = 0
}

struct Preset: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    // Live capture tuning (device-level). Not all devices support all ranges.
    var exposureBias: Float? = nil // -8.0 ... +8.0 typical
    var temperature: Float? = nil  // in Kelvin-like scale (approx for WB lock helper)
    var tint: Float? = nil         // green-magenta shift
    // Post processing (Core Image)
    var exposureEV: Float? = nil   // CIExposureAdjust inputEV, e.g. -1.0...+1.0
    var temperatureShift: Float? = nil // CITemperatureAndTint delta
    var tintShift: Float? = nil
    var vibrance: Float? = nil     // -1 ... +1
    var saturation: Float? = nil   // 0 ... 2
    var contrast: Float? = nil     // 0.5 ... 1.5
}

struct PhotoTemplate: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var description: String
    var overlay: [OverlayElement]
    var preset: Preset
}

// MARK: - Sample Templates
struct SampleTemplates {
    static let ruleOfThirdsPortrait = PhotoTemplate(
        name: "Rule of Thirds Portrait",
        description: "Align subject eyes on top horizontal; center body on left vertical.",
        overlay: [
            .init(kind: .grid, gridRows: 3, gridCols: 3),
            .init(kind: .ellipse, rect: CGRect(x: 0.55, y: 0.25, width: 0.08, height: 0.08)),
            .init(kind: .ellipse, rect: CGRect(x: 0.55, y: 0.45, width: 0.08, height: 0.08))
        ],
        preset: Preset(
            name: "Soft Portrait",
            exposureBias: 0.3,
            temperature: 5200,
            tint: 0,
            exposureEV: 0.2,
            vibrance: 0.2,
            saturation: 1.05,
            contrast: 1.03
        )
    )

    static let foodOverhead = PhotoTemplate(
        name: "Food Overhead (Flat Lay)",
        description: "Top-down grid with plate center and radial guide.",
        overlay: [
            .init(kind: .grid, gridRows: 2, gridCols: 2),
            .init(kind: .ellipse, rect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)),
            .init(kind: .path, points: [CGPoint(x: 0.5, y: 0.0), CGPoint(x: 0.5, y: 1.0)])
        ],
        preset: Preset(
            name: "Crisp Food",
            exposureBias: 0.1,
            temperature: 4800,
            tint: -5,
            exposureEV: 0.1,
            vibrance: 0.25,
            saturation: 1.08,
            contrast: 1.07
        )
    )

    static let all: [PhotoTemplate] = [ruleOfThirdsPortrait, foodOverhead]
}

// MARK: - Camera Manager
final class CameraManager: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    @Published var isSessionRunning = false
    #if canImport(UIKit)
    @Published var latestPhoto: UIImage? = nil
    #else
    @Published var latestPhoto: NSImage? = nil
    #endif
    @Published var authorizationStatus: AVAuthorizationStatus = .notDetermined

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let photoOutput = AVCapturePhotoOutput()
    private var videoDevice: AVCaptureDevice?

    var activePreset: Preset? { didSet { applyLivePreset() } }

    override init() {
        super.init()
        checkPermissions()
        configureSession()
    }

    func checkPermissions() {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if authorizationStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.authorizationStatus = granted ? .authorized : .denied
                }
            }
        }
    }

    private func configureSession() {
        sessionQueue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            // Input
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                print("No back camera")
                self.session.commitConfiguration()
                return
            }
            self.videoDevice = device
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(input) { self.session.addInput(input) }
            } catch {
                print("Input error: \(error)")
            }

            // Output
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
                #if os(iOS)
                self.photoOutput.isHighResolutionCaptureEnabled = true
                #endif
            }

            self.session.commitConfiguration()
        }
    }

    func start() {
        sessionQueue.async {
            if !self.session.isRunning { self.session.startRunning(); DispatchQueue.main.async { self.isSessionRunning = true } }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning(); DispatchQueue.main.async { self.isSessionRunning = false } }
        }
    }

    // Live device-level tuning
    private func applyLivePreset() {
        guard let device = videoDevice, let preset = activePreset else { return }
        sessionQueue.async {
            do { try device.lockForConfiguration() } catch { return }

            #if os(iOS)
            if let bias = preset.exposureBias, device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
                let minBias = device.minExposureTargetBias
                let maxBias = device.maxExposureTargetBias
                let clamped = max(min(bias, maxBias), minBias)
                device.setExposureTargetBias(clamped) { _ in }
            }

            if device.isWhiteBalanceModeSupported(.locked), let temp = preset.temperature { // approximate helper
                let tint = preset.tint ?? 0
                let gains = CameraManager.deviceGains(for: device, temperature: temp, tint: tint)
                device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
            }
            #endif

            device.unlockForConfiguration()
        }
    }

    // Helper: convert temperature/tint to device gains
    #if os(iOS)
    static func deviceGains(for device: AVCaptureDevice, temperature: Float, tint: Float) -> AVCaptureDevice.WhiteBalanceGains {
        let tempTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: temperature, tint: tint)
        var gains = device.deviceWhiteBalanceGains(for: tempTint)
        // clamp to valid ranges
        gains.redGain = max(1.0, min(gains.redGain, device.maxWhiteBalanceGain))
        gains.greenGain = max(1.0, min(gains.greenGain, device.maxWhiteBalanceGain))
        gains.blueGain = max(1.0, min(gains.blueGain, device.maxWhiteBalanceGain))
        return gains
    }
    #endif

    // Capture & post-process
    func capture(preset: Preset?) {
        let settings = AVCapturePhotoSettings()
        #if os(iOS)
        settings.isHighResolutionPhotoEnabled = true
        #endif
        if self.photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
            settings.flashMode = .off
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
        self.pendingPreset = preset
    }

    private var pendingPreset: Preset?

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            print("Photo error: \(String(describing: error))"); return
        }
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data) else { return }
        let processed = applyFilters(to: uiImage, with: pendingPreset)
        DispatchQueue.main.async { self.latestPhoto = processed }
        saveToPhotos(processed)
        #else
        guard let nsImage = NSImage(data: data) else { return }
        DispatchQueue.main.async { self.latestPhoto = nsImage }
        #endif
    }

    #if canImport(UIKit)
    private func applyFilters(to image: UIImage, with preset: Preset?) -> UIImage {
        guard let preset = preset else { return image }
        let context = CIContext()
        guard let ciImage = CIImage(image: image) else { return image }
        var output = ciImage
        if let ev = preset.exposureEV {
            let f = CIFilter.exposureAdjust(); f.inputImage = output; f.ev = ev; output = f.outputImage ?? output
        }
        if let ts = preset.temperatureShift, let tt = preset.tintShift {
            let f = CIFilter.temperatureAndTint(); f.inputImage = output; f.neutral = CIVector(x: CGFloat(6500 + ts), y: CGFloat(0 + tt)); output = f.outputImage ?? output
        }
        if let v = preset.vibrance {
            let f = CIFilter.vibrance(); f.inputImage = output; f.amount = v; output = f.outputImage ?? output
        }
        if let s = preset.saturation { let f = CIFilter.colorControls(); f.inputImage = output; f.saturation = s; output = f.outputImage ?? output }
        if let c = preset.contrast { let f = CIFilter.colorControls(); f.inputImage = output; f.contrast = c; output = f.outputImage ?? output }
        if let cgImage = context.createCGImage(output, from: output.extent) { return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation) }
        return image
    }
    #endif

    #if canImport(UIKit)
    private func saveToPhotos(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, error in
                if let error = error { print("Save error: \(error)") }
            }
        }
    }
    #endif
}

// MARK: - Preview Layer Wrapper
#if os(iOS)
struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var manager: CameraManager

    func makeUIView(context: Context) -> PreviewUIView { PreviewUIView(session: manager.session) }
    func updateUIView(_ uiView: PreviewUIView, context: Context) { }

    final class PreviewUIView: UIView {
        private var videoPreviewLayer: AVCaptureVideoPreviewLayer
        init(session: AVCaptureSession) {
            self.videoPreviewLayer = AVCaptureVideoPreviewLayer(session: session)
            super.init(frame: .zero)
            videoPreviewLayer.videoGravity = .resizeAspectFill
            layer.addSublayer(videoPreviewLayer)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            videoPreviewLayer.frame = bounds
            CATransaction.commit()
        }
    }
}
#else
// Fallback for macOS - just a placeholder view
struct CameraPreviewView: View {
    @ObservedObject var manager: CameraManager
    
    var body: some View {
        Rectangle()
            .fill(Color.black)
            .overlay(
                Text("Camera Preview\n(Not available on macOS)")
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            )
    }
}
#endif

// MARK: - Overlay Renderer
struct TemplateOverlayView: View {
    var elements: [OverlayElement]
    var lineWidth: CGFloat = 2
    var color: Color = .white.opacity(0.8)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(elements) { el in
                    switch el.kind {
                    case .grid:
                        grid(in: geo.size, rows: el.gridRows, cols: el.gridCols)
                            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, dash: [6,6]))
                    case .rect:
                        pathForRect(el.rect, in: geo.size).stroke(color, lineWidth: lineWidth)
                    case .ellipse:
                        pathForEllipse(el.rect, in: geo.size).stroke(color, lineWidth: lineWidth)
                    case .line:
                        pathForLine(el.points, in: geo.size).stroke(color, lineWidth: lineWidth)
                    case .path:
                        pathForPolyline(el.points, in: geo.size).stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func denorm(_ p: CGPoint, _ size: CGSize) -> CGPoint { .init(x: p.x * size.width, y: p.y * size.height) }

    private func grid(in size: CGSize, rows: Int, cols: Int) -> Path {
        var path = Path()
        guard rows > 0 && cols > 0 else { return path }
        let rowH = size.height / CGFloat(rows)
        let colW = size.width / CGFloat(cols)
        for r in 1..<rows { let y = CGFloat(r) * rowH; path.move(to: .init(x: 0, y: y)); path.addLine(to: .init(x: size.width, y: y)) }
        for c in 1..<cols { let x = CGFloat(c) * colW; path.move(to: .init(x: x, y: 0)); path.addLine(to: .init(x: x, y: size.height)) }
        return path
    }

    private func pathForRect(_ rect: CGRect, in size: CGSize) -> Path {
        let r = CGRect(
            x: rect.origin.x * size.width,
            y: rect.origin.y * size.height,
            width: rect.size.width * size.width,
            height: rect.size.height * size.height
        )
        return Path(roundedRect: r, cornerRadius: 4)
    }

    private func pathForEllipse(_ rect: CGRect, in size: CGSize) -> Path {
        let r = CGRect(
            x: rect.origin.x * size.width,
            y: rect.origin.y * size.height,
            width: rect.size.width * size.width,
            height: rect.size.height * size.height
        )
        var p = Path()
        p.addEllipse(in: r)
        return p
    }

    private func pathForLine(_ points: [CGPoint], in size: CGSize) -> Path {
        var p = Path()
        guard points.count >= 2 else { return p }
        p.move(to: denorm(points[0], size))
        p.addLine(to: denorm(points[1], size))
        return p
    }

    private func pathForPolyline(_ points: [CGPoint], in size: CGSize) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: denorm(first, size))
        for pt in points.dropFirst() { p.addLine(to: denorm(pt, size)) }
        return p
    }
}

// MARK: - UI
struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @State private var templates: [PhotoTemplate] = SampleTemplates.all
    @State private var currentTemplateIndex: Int = 0
    @State private var showGallery = false
    @State private var overlayOpacity: Double = 0.9

    private var currentTemplate: PhotoTemplate { templates[currentTemplateIndex] }

    var body: some View {
        ZStack {
            CameraPreviewView(manager: camera).ignoresSafeArea()

            // Overlay
            TemplateOverlayView(elements: currentTemplate.overlay)
                .opacity(overlayOpacity)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(currentTemplate.name).font(.headline).padding(.top, 8)
                        Text(currentTemplate.description).font(.caption)
                    }
                    .padding(12)
                    .background(.black.opacity(0.4))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding()
                }

            // Controls
            VStack {
                Spacer()
                controlBar
            }
        }
        .onAppear { camera.start(); camera.activePreset = currentTemplate.preset }
        .onDisappear { camera.stop() }
    }

    private var controlBar: some View {
        HStack(spacing: 12) {
            // Template picker
            Menu {
                ForEach(templates.indices, id: \.self) { idx in
                    Button(action: { selectTemplate(idx) }) {
                        Label(templates[idx].name, systemImage: idx == currentTemplateIndex ? "checkmark" : "")
                    }
                }
            } label: {
                labelCapsule(title: "Template", system: "square.grid.3x3")
            }

            // Opacity
            HStack(spacing: 8) {
                Image(systemName: "eye")
                Slider(value: $overlayOpacity, in: 0...1)
            }
            .padding(10)
            .background(.black.opacity(0.4))
            .foregroundStyle(.white)
            .clipShape(Capsule())

            // Capture
            Button(action: { camera.capture(preset: currentTemplate.preset) }) {
                Circle().stroke(.white, lineWidth: 6).frame(width: 72, height: 72)
                    .overlay(Circle().fill(.white.opacity(0.2)).frame(width: 56, height: 56))
            }

            // Last photo preview
            if let img = camera.latestPhoto {
                Button { showGallery.toggle() } label: {
                    #if canImport(UIKit)
                    Image(uiImage: img).resizable().scaledToFill().frame(width: 48, height: 48).clipped().cornerRadius(6)
                    #else
                    Image(nsImage: img).resizable().scaledToFill().frame(width: 48, height: 48).clipped().cornerRadius(6)
                    #endif
                }
                .sheet(isPresented: $showGallery) {
                    VStack { 
                        #if canImport(UIKit)
                        Image(uiImage: img).resizable().scaledToFit()
                        #else
                        Image(nsImage: img).resizable().scaledToFit()
                        #endif
                        Text("Saved to Photos").padding() 
                    }
                    .presentationDetents([.medium, .large])
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 24)
    }

    private func labelCapsule(title: String, system: String) -> some View {
        HStack(spacing: 8) { Image(systemName: system); Text(title) }
            .padding(10)
            .background(.black.opacity(0.4))
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }

    private func selectTemplate(_ idx: Int) {
        currentTemplateIndex = idx
        camera.activePreset = templates[idx].preset
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

/*
 Notes:
 - Live "presets" are approximated via exposure bias and white balance lock; exact ISO/shutter control requires custom exposure configuration and is constrained in AVCapture.
 - Additional overlays can be defined with normalized coordinates in PhotoTemplate.overlay.
 - Extend Preset with more CI filters (e.g., clarity/sharpening via CIUnsharpMask, highlights/shadows via CIHighlightShadowAdjust).
 - Consider using AVCapturePhotoSettings.embeddedThumbnailPhotoFormat to speed up preview.
 - For PRO modes, enable manual exposure/ISO where supported, with device.setExposureModeCustom().
 */
