import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif
import AVFoundation
import Photos
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO

@main
struct TemplateCamApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(appState)
        }
    }
}

// MARK: - Persistence Manager
class PersistenceManager {
    static let shared = PersistenceManager()

    private let userProfileKey = "userProfile"
    private let savedTemplateIdsKey = "savedTemplateIds"

    func saveUserProfile(_ profile: UserProfile) {
        if let encoded = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(encoded, forKey: userProfileKey)
        }
    }

    func loadUserProfile() -> UserProfile? {
        guard let data = UserDefaults.standard.data(forKey: userProfileKey),
              let profile = try? JSONDecoder().decode(UserProfile.self, from: data) else {
            return nil
        }
        return profile
    }

    func saveSavedTemplateIds(_ ids: [UUID]) {
        let idStrings = ids.map { $0.uuidString }
        UserDefaults.standard.set(idStrings, forKey: savedTemplateIdsKey)
    }

    func loadSavedTemplateIds() -> [UUID] {
        guard let idStrings = UserDefaults.standard.array(forKey: savedTemplateIdsKey) as? [String] else {
            return []
        }
        return idStrings.compactMap { UUID(uuidString: $0) }
    }
}

// MARK: - App State
class AppState: ObservableObject {
    @Published var userProfile: UserProfile {
        didSet {
            PersistenceManager.shared.saveUserProfile(userProfile)
        }
    }
    @Published var templates: [PhotoTemplate]
    @Published var selectedTemplate: PhotoTemplate?

    init() {
        // Load user profile from persistence or use default
        if let savedProfile = PersistenceManager.shared.loadUserProfile() {
            self.userProfile = savedProfile
        } else {
            self.userProfile = UserProfile(
                username: "PhotoEnthusiast",
                bio: "Capturing moments with perfect composition",
                savedTemplateIds: []
            )
        }

        // Load saved template IDs
        let savedIds = PersistenceManager.shared.loadSavedTemplateIds()
        if !savedIds.isEmpty {
            self.userProfile.savedTemplateIds = savedIds
        }

        self.templates = SampleTemplates.all
    }

    func toggleSaveTemplate(_ template: PhotoTemplate) {
        if let index = userProfile.savedTemplateIds.firstIndex(of: template.id) {
            userProfile.savedTemplateIds.remove(at: index)
        } else {
            userProfile.savedTemplateIds.append(template.id)
        }
        PersistenceManager.shared.saveSavedTemplateIds(userProfile.savedTemplateIds)
    }

    func isSaved(_ template: PhotoTemplate) -> Bool {
        userProfile.savedTemplateIds.contains(template.id)
    }

    var savedTemplates: [PhotoTemplate] {
        templates.filter { userProfile.savedTemplateIds.contains($0.id) }
    }
}

// MARK: - Models
struct UserProfile: Codable {
    var username: String
    var bio: String
    var savedTemplateIds: [UUID]
}

struct OverlayElement: Identifiable, Codable {
    enum Kind: String, Codable { case line, rect, ellipse, path, grid }
    var id: UUID = UUID()
    var kind: Kind
    var points: [CGPoint] = []
    var rect: CGRect = .zero
    var gridRows: Int = 0
    var gridCols: Int = 0
}

struct Preset: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var exposureBias: Float? = nil
    var temperature: Float? = nil
    var tint: Float? = nil
    var exposureEV: Float? = nil
    var temperatureShift: Float? = nil
    var tintShift: Float? = nil
    var vibrance: Float? = nil
    var saturation: Float? = nil
    var contrast: Float? = nil
    var highlights: Float? = nil
    var shadows: Float? = nil
    var clarity: Float? = nil
    var lutFileName: String? = nil
    var lutIntensity: Float? = nil
}

struct PhotoTemplate: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var description: String
    var category: String
    var overlay: [OverlayElement]
    var preset: Preset
    var isPopular: Bool = false

    static func == (lhs: PhotoTemplate, rhs: PhotoTemplate) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Template Loader
class TemplateLoader {
    static let shared = TemplateLoader()

    func loadTemplates() -> [PhotoTemplate] {
        guard let url = Bundle.main.url(forResource: "Templates", withExtension: "json") else {
            print("Templates.json not found, using hardcoded templates")
            return SampleTemplates.hardcodedTemplates
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let templateData = try decoder.decode(TemplateData.self, from: data)

            return templateData.templates.map { jsonTemplate in
                PhotoTemplate(
                    id: UUID(uuidString: jsonTemplate.id) ?? UUID(),
                    name: jsonTemplate.name,
                    description: jsonTemplate.description,
                    category: jsonTemplate.category,
                    overlay: jsonTemplate.overlay.elements.map { element in
                        OverlayElement(
                            kind: OverlayElement.Kind(rawValue: element.kind) ?? .line,
                            points: element.points?.map { CGPoint(x: $0.x, y: $0.y) } ?? [],
                            rect: element.rect.map { CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) } ?? .zero,
                            gridRows: element.gridRows ?? 0,
                            gridCols: element.gridCols ?? 0
                        )
                    },
                    preset: Preset(
                        name: jsonTemplate.preset.name,
                        exposureBias: jsonTemplate.preset.exposureBias,
                        temperature: jsonTemplate.preset.temperature,
                        tint: jsonTemplate.preset.tint,
                        exposureEV: jsonTemplate.preset.exposureEV,
                        temperatureShift: jsonTemplate.preset.temperatureShift,
                        tintShift: jsonTemplate.preset.tintShift,
                        vibrance: jsonTemplate.preset.vibrance,
                        saturation: jsonTemplate.preset.saturation,
                        contrast: jsonTemplate.preset.contrast,
                        highlights: jsonTemplate.preset.highlights,
                        shadows: jsonTemplate.preset.shadows,
                        clarity: jsonTemplate.preset.clarity,
                        lutFileName: jsonTemplate.preset.lutFileName,
                        lutIntensity: jsonTemplate.preset.lutIntensity
                    ),
                    isPopular: jsonTemplate.isPopular
                )
            }
        } catch {
            print("Error loading templates: \(error)")
            return SampleTemplates.hardcodedTemplates
        }
    }
}

// MARK: - Template JSON Models
struct TemplateData: Codable {
    let version: String
    let templates: [JSONTemplate]
}

struct JSONTemplate: Codable {
    let id: String
    let name: String
    let description: String
    let category: String
    let isPopular: Bool
    let thumbnail: String?
    let overlay: JSONOverlay
    let preset: JSONPreset
}

struct JSONOverlay: Codable {
    let elements: [JSONOverlayElement]
}

struct JSONOverlayElement: Codable {
    let kind: String
    let points: [JSONPoint]?
    let rect: JSONRect?
    let gridRows: Int?
    let gridCols: Int?
}

struct JSONPoint: Codable {
    let x: Double
    let y: Double
}

struct JSONRect: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct JSONPreset: Codable {
    let name: String
    let exposureBias: Float?
    let temperature: Float?
    let tint: Float?
    let exposureEV: Float?
    let temperatureShift: Float?
    let tintShift: Float?
    let vibrance: Float?
    let saturation: Float?
    let contrast: Float?
    let highlights: Float?
    let shadows: Float?
    let clarity: Float?
    let lutFileName: String?
    let lutIntensity: Float?
}

// MARK: - Sample Templates
struct SampleTemplates {
    static let ruleOfThirdsPortrait = PhotoTemplate(
        name: "Portrait Classic",
        description: "Align subject's eyes on the top third line for perfect portrait composition",
        category: "Portrait",
        overlay: [
            .init(kind: .grid, gridRows: 3, gridCols: 3),
            .init(kind: .ellipse, rect: CGRect(x: 0.30, y: 0.25, width: 0.08, height: 0.05)),
            .init(kind: .ellipse, rect: CGRect(x: 0.62, y: 0.25, width: 0.08, height: 0.05))
        ],
        preset: Preset(
            name: "Soft Portrait",
            exposureBias: 0.3,
            exposureEV: 0.2,
            vibrance: 0.2,
            saturation: 1.05,
            contrast: 1.03
        ),
        isPopular: true
    )

    static let foodOverhead = PhotoTemplate(
        name: "Flat Lay",
        description: "Perfect overhead view for food and product photography",
        category: "Food",
        overlay: [
            .init(kind: .grid, gridRows: 2, gridCols: 2),
            .init(kind: .ellipse, rect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)),
            .init(kind: .path, points: [CGPoint(x: 0.5, y: 0.0), CGPoint(x: 0.5, y: 1.0)])
        ],
        preset: Preset(
            name: "Crisp Food",
            exposureBias: 0.1,
            exposureEV: 0.1,
            vibrance: 0.25,
            saturation: 1.08,
            contrast: 1.07
        ),
        isPopular: true
    )

    static let goldenRatioLandscape = PhotoTemplate(
        name: "Golden Hour",
        description: "Golden ratio spiral for stunning landscape compositions",
        category: "Landscape",
        overlay: [
            .init(kind: .grid, gridRows: 3, gridCols: 3),
            .init(kind: .path, points: [
                CGPoint(x: 0.0, y: 0.618),
                CGPoint(x: 1.0, y: 0.618)
            ])
        ],
        preset: Preset(
            name: "Warm Landscape",
            exposureBias: -0.2,
            exposureEV: -0.1,
            vibrance: 0.3,
            saturation: 1.1,
            contrast: 1.05
        ),
        isPopular: true
    )

    static let symmetricalArchitecture = PhotoTemplate(
        name: "Symmetry",
        description: "Perfect symmetry for architectural and geometric shots",
        category: "Architecture",
        overlay: [
            .init(kind: .path, points: [CGPoint(x: 0.5, y: 0.0), CGPoint(x: 0.5, y: 1.0)]),
            .init(kind: .path, points: [CGPoint(x: 0.0, y: 0.5), CGPoint(x: 1.0, y: 0.5)]),
            .init(kind: .grid, gridRows: 4, gridCols: 4)
        ],
        preset: Preset(
            name: "Sharp Architecture",
            exposureBias: -0.3,
            exposureEV: 0.0,
            vibrance: 0.1,
            saturation: 0.95,
            contrast: 1.15
        ),
        isPopular: false
    )

    static let centerFocus = PhotoTemplate(
        name: "Center Stage",
        description: "Center composition for powerful, focused subjects",
        category: "Product",
        overlay: [
            .init(kind: .ellipse, rect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)),
            .init(kind: .ellipse, rect: CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3))
        ],
        preset: Preset(
            name: "Clean Product",
            exposureBias: 0.5,
            exposureEV: 0.3,
            vibrance: 0.15,
            saturation: 1.0,
            contrast: 1.08
        ),
        isPopular: false
    )

    static let diagonalDynamic = PhotoTemplate(
        name: "Dynamic Diagonal",
        description: "Diagonal leading lines for action and movement",
        category: "Action",
        overlay: [
            .init(kind: .path, points: [CGPoint(x: 0.0, y: 0.0), CGPoint(x: 1.0, y: 1.0)]),
            .init(kind: .path, points: [CGPoint(x: 0.0, y: 1.0), CGPoint(x: 1.0, y: 0.0)]),
            .init(kind: .grid, gridRows: 3, gridCols: 3)
        ],
        preset: Preset(
            name: "Energetic",
            exposureBias: 0.0,
            exposureEV: 0.0,
            vibrance: 0.35,
            saturation: 1.12,
            contrast: 1.1
        ),
        isPopular: true
    )

    static let minimalist = PhotoTemplate(
        name: "Minimalist",
        description: "Negative space composition for clean, minimal aesthetics",
        category: "Minimal",
        overlay: [
            .init(kind: .rect, rect: CGRect(x: 0.6, y: 0.6, width: 0.3, height: 0.3)),
            .init(kind: .path, points: [CGPoint(x: 0.0, y: 0.618), CGPoint(x: 1.0, y: 0.618)])
        ],
        preset: Preset(
            name: "Soft Minimal",
            exposureBias: 0.7,
            exposureEV: 0.4,
            vibrance: 0.0,
            saturation: 0.85,
            contrast: 0.95
        ),
        isPopular: false
    )

    static let frameWithin = PhotoTemplate(
        name: "Frame Within",
        description: "Natural framing for depth and focus",
        category: "Creative",
        overlay: [
            .init(kind: .rect, rect: CGRect(x: 0.15, y: 0.15, width: 0.7, height: 0.7)),
            .init(kind: .rect, rect: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4))
        ],
        preset: Preset(
            name: "Depth Focus",
            exposureBias: 0.2,
            exposureEV: 0.1,
            vibrance: 0.2,
            saturation: 1.05,
            contrast: 1.06
        ),
        isPopular: true
    )

    static let hardcodedTemplates: [PhotoTemplate] = [
        ruleOfThirdsPortrait,
        foodOverhead,
        goldenRatioLandscape,
        symmetricalArchitecture,
        centerFocus,
        diagonalDynamic,
        minimalist,
        frameWithin
    ]

    static let all: [PhotoTemplate] = TemplateLoader.shared.loadTemplates()
    static let popular: [PhotoTemplate] = all.filter { $0.isPopular }
}

// MARK: - Filter Processor
final class FilterProcessor {
    static let shared = FilterProcessor()

    #if os(iOS)
    let context: CIContext = {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return CIContext()
        }
        return CIContext(mtlDevice: device, options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.displayP3) as Any,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.displayP3) as Any,
            .cacheIntermediates: true
        ])
    }()
    #else
    let context = CIContext()
    #endif

    private var lutCache: [String: CIImage] = [:]

    func applyPreset(_ preset: Preset, to image: CIImage) -> CIImage {
        var output = image

        // Exposure adjustment
        if let ev = preset.exposureEV {
            let filter = CIFilter.exposureAdjust()
            filter.inputImage = output
            filter.ev = ev
            output = filter.outputImage ?? output
        }

        // Temperature and Tint
        if let temp = preset.temperatureShift, let tint = preset.tintShift {
            let filter = CIFilter.temperatureAndTint()
            filter.inputImage = output
            // Neutral values
            filter.neutral = CIVector(x: 6500, y: 0)
            // Target values (shift from neutral)
            filter.targetNeutral = CIVector(x: 6500 + CGFloat(temp * 1000), y: CGFloat(tint * 100))
            output = filter.outputImage ?? output
        } else if let temp = preset.temperature, let tint = preset.tint {
            let filter = CIFilter.temperatureAndTint()
            filter.inputImage = output
            filter.neutral = CIVector(x: 6500, y: 0)
            filter.targetNeutral = CIVector(x: CGFloat(temp), y: CGFloat(tint))
            output = filter.outputImage ?? output
        }

        // Highlights adjustment (using CIHighlightShadowAdjust)
        if let highlights = preset.highlights, let shadows = preset.shadows {
            let filter = CIFilter.highlightShadowAdjust()
            filter.inputImage = output
            filter.highlightAmount = highlights
            filter.shadowAmount = shadows
            output = filter.outputImage ?? output
        } else if let highlights = preset.highlights {
            let filter = CIFilter.highlightShadowAdjust()
            filter.inputImage = output
            filter.highlightAmount = highlights
            output = filter.outputImage ?? output
        } else if let shadows = preset.shadows {
            let filter = CIFilter.highlightShadowAdjust()
            filter.inputImage = output
            filter.shadowAmount = shadows
            output = filter.outputImage ?? output
        }

        // Vibrance
        if let vibrance = preset.vibrance {
            let filter = CIFilter.vibrance()
            filter.inputImage = output
            filter.amount = vibrance
            output = filter.outputImage ?? output
        }

        // Color Controls (Saturation & Contrast combined)
        if preset.saturation != nil || preset.contrast != nil {
            let filter = CIFilter.colorControls()
            filter.inputImage = output
            filter.saturation = preset.saturation ?? 1.0
            filter.contrast = preset.contrast ?? 1.0
            output = filter.outputImage ?? output
        }

        // Clarity (using unsharp mask)
        if let clarity = preset.clarity, clarity != 0 {
            let filter = CIFilter.unsharpMask()
            filter.inputImage = output
            filter.radius = 2.5
            filter.intensity = clarity
            output = filter.outputImage ?? output
        }

        // LUT (Color Cube)
        if let lutFile = preset.lutFileName, let intensity = preset.lutIntensity {
            if let lutImage = loadLUT(fileName: lutFile) {
                let filter = CIFilter.colorCubeWithColorSpace()
                filter.inputImage = output
                filter.cubeDimension = 64
                filter.cubeData = lutImage
                filter.colorSpace = CGColorSpace(name: CGColorSpace.displayP3)

                if let lutOutput = filter.outputImage {
                    // Blend LUT with original based on intensity
                    if intensity < 1.0 {
                        let blendFilter = CIFilter.sourceOverCompositing()
                        blendFilter.inputImage = lutOutput
                        blendFilter.backgroundImage = output
                        // Apply intensity by adjusting opacity
                        let opacityFilter = CIFilter.colorMatrix()
                        opacityFilter?.inputImage = lutOutput
                        opacityFilter?.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
                        opacityFilter?.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
                        opacityFilter?.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
                        opacityFilter?.setValue(CIVector(x: 0, y: 0, z: 0, w: CGFloat(intensity)), forKey: "inputAVector")
                        output = opacityFilter?.outputImage ?? lutOutput
                    } else {
                        output = lutOutput
                    }
                }
            }
        }

        return output
    }

    private func loadLUT(fileName: String) -> Data? {
        // Try to load .cube file from bundle
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "cube") else {
            return nil
        }

        do {
            let content = try String(contentsOf: url)
            return parseCubeLUT(content: content)
        } catch {
            print("Error loading LUT: \(error)")
            return nil
        }
    }

    private func parseCubeLUT(content: String) -> Data? {
        // Parse .cube LUT format
        var size = 64
        var values: [Float] = []

        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("LUT_3D_SIZE") {
                let components = trimmed.components(separatedBy: .whitespaces)
                if components.count > 1, let s = Int(components[1]) {
                    size = s
                }
            } else if !trimmed.isEmpty && !trimmed.hasPrefix("#") && !trimmed.hasPrefix("TITLE") && !trimmed.hasPrefix("DOMAIN") {
                let components = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if components.count >= 3 {
                    if let r = Float(components[0]), let g = Float(components[1]), let b = Float(components[2]) {
                        values.append(r)
                        values.append(g)
                        values.append(b)
                        values.append(1.0) // alpha
                    }
                }
            }
        }

        guard values.count == size * size * size * 4 else {
            return nil
        }

        return Data(bytes: &values, count: values.count * MemoryLayout<Float>.size)
    }
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
    @Published var currentCameraPosition: AVCaptureDevice.Position = .back
    @Published var zoomFactor: CGFloat = 1.0
    @Published var isProcessing = false

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let photoOutput = AVCapturePhotoOutput()
    private var videoDevice: AVCaptureDevice?
    private var currentInput: AVCaptureDeviceInput?

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

            self.setupCamera(position: .back)

            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
                #if os(iOS)
                self.photoOutput.isHighResolutionCaptureEnabled = true
                #endif
            }

            self.session.commitConfiguration()
        }
    }

    private func setupCamera(position: AVCaptureDevice.Position) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            print("No camera for position \(position)")
            return
        }

        self.videoDevice = device

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if let currentInput = self.currentInput {
                self.session.removeInput(currentInput)
            }
            if self.session.canAddInput(input) {
                self.session.addInput(input)
                self.currentInput = input
            }

            // Configure 60fps if available
            #if os(iOS)
            try device.lockForConfiguration()

            // Find best format supporting 60fps
            let formats = device.formats
            var bestFormat: AVCaptureDevice.Format?
            var bestFrameRate: Double = 0

            for format in formats {
                for range in format.videoSupportedFrameRateRanges {
                    if range.maxFrameRate >= 60 && range.maxFrameRate > bestFrameRate {
                        bestFormat = format
                        bestFrameRate = range.maxFrameRate
                    }
                }
            }

            if let format = bestFormat {
                device.activeFormat = format
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 60)
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 60)
            }

            device.unlockForConfiguration()
            #endif
        } catch {
            print("Camera setup error: \(error)")
        }
    }

    func toggleCamera() {
        let newPosition: AVCaptureDevice.Position = currentCameraPosition == .back ? .front : .back
        sessionQueue.async {
            self.session.beginConfiguration()
            self.setupCamera(position: newPosition)
            self.session.commitConfiguration()

            DispatchQueue.main.async {
                self.currentCameraPosition = newPosition
            }
        }
    }

    func setZoom(_ factor: CGFloat) {
        guard let device = videoDevice else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                let clampedFactor = max(1.0, min(factor, device.activeFormat.videoMaxZoomFactor))
                device.videoZoomFactor = clampedFactor
                device.unlockForConfiguration()

                DispatchQueue.main.async {
                    self.zoomFactor = clampedFactor
                }
            } catch {
                print("Zoom error: \(error)")
            }
        }
    }

    func focusAndExpose(at point: CGPoint) {
        guard let device = videoDevice else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()

                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = point
                    device.focusMode = .autoFocus
                }

                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                    device.exposurePointOfInterest = point
                    device.exposureMode = .autoExpose
                }

                device.unlockForConfiguration()
            } catch {
                print("Focus/Expose error: \(error)")
            }
        }
    }

    func start() {
        sessionQueue.async {
            if !self.session.isRunning {
                self.session.startRunning()
                DispatchQueue.main.async { self.isSessionRunning = true }
            }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
                DispatchQueue.main.async { self.isSessionRunning = false }
            }
        }
    }

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

            // Use continuous auto white balance instead of locking
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            #endif

            device.unlockForConfiguration()
        }
    }

    #if os(iOS)
    static func deviceGains(for device: AVCaptureDevice, temperature: Float, tint: Float) -> AVCaptureDevice.WhiteBalanceGains {
        let tempTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: temperature, tint: tint)
        var gains = device.deviceWhiteBalanceGains(for: tempTint)
        gains.redGain = max(1.0, min(gains.redGain, device.maxWhiteBalanceGain))
        gains.greenGain = max(1.0, min(gains.greenGain, device.maxWhiteBalanceGain))
        gains.blueGain = max(1.0, min(gains.blueGain, device.maxWhiteBalanceGain))
        return gains
    }
    #endif

    func capture(preset: Preset?) {
        DispatchQueue.main.async {
            self.isProcessing = true
        }

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
            print("Photo error: \(String(describing: error))")
            DispatchQueue.main.async {
                self.isProcessing = false
            }
            return
        }
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data) else {
            DispatchQueue.main.async {
                self.isProcessing = false
            }
            return
        }

        // Process image off the main thread
        DispatchQueue.global(qos: .userInitiated).async {
            let processed = self.applyFilters(to: uiImage, with: self.pendingPreset)
            DispatchQueue.main.async {
                self.latestPhoto = processed
                self.isProcessing = false
            }
            self.saveToPhotos(processed)
        }
        #else
        guard let nsImage = NSImage(data: data) else {
            DispatchQueue.main.async {
                self.isProcessing = false
            }
            return
        }
        DispatchQueue.main.async {
            self.latestPhoto = nsImage
            self.isProcessing = false
        }
        #endif
    }

    #if canImport(UIKit)
    private func applyFilters(to image: UIImage, with preset: Preset?) -> UIImage {
        guard let preset = preset else { return image }
        guard let ciImage = CIImage(image: image) else { return image }
        let filtered = FilterProcessor.shared.applyPreset(preset, to: ciImage)

        // Use Display P3 color space if available
        let colorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()

        if let cgImage = FilterProcessor.shared.context.createCGImage(filtered, from: filtered.extent, format: .RGBA8, colorSpace: colorSpace) {
            return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
        }
        return image
    }
    #endif

    #if canImport(UIKit)
    private func saveToPhotos(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else { return }

            // Convert to high-quality JPEG with Display P3
            let colorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
            guard let cgImage = image.cgImage else {
                // Fallback to regular save
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }) { success, error in
                    if let error = error { print("Save error: \(error)") }
                }
                return
            }

            // Create high-quality JPEG data
            let mutableData = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(mutableData as CFMutableData, "public.jpeg" as CFString, 1, nil) else {
                return
            }

            let options: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: 0.9,
                kCGImagePropertyOrientation: image.imageOrientation.cgImagePropertyOrientation,
                kCGImageDestinationEmbedThumbnail: true
            ]

            CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
            CGImageDestinationFinalize(destination)

            // Save to photo library
            PHPhotoLibrary.shared().performChanges({
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(with: .photo, data: mutableData as Data, options: nil)
            }) { success, error in
                if let error = error {
                    print("Save error: \(error)")
                } else if success {
                    print("Photo saved successfully with Display P3 color space")
                }
            }
        }
    }
    #endif
}

// MARK: - Camera Preview
#if os(iOS)
struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var manager: CameraManager

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView(session: manager.session, manager: manager)
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) { }

    final class PreviewUIView: UIView {
        private var videoPreviewLayer: AVCaptureVideoPreviewLayer
        private weak var manager: CameraManager?
        private var initialZoom: CGFloat = 1.0

        init(session: AVCaptureSession, manager: CameraManager) {
            self.videoPreviewLayer = AVCaptureVideoPreviewLayer(session: session)
            self.manager = manager
            super.init(frame: .zero)
            videoPreviewLayer.videoGravity = .resizeAspect
            layer.addSublayer(videoPreviewLayer)

            // Add tap gesture for focus/expose
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            addGestureRecognizer(tapGesture)

            // Add pinch gesture for zoom
            let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            addGestureRecognizer(pinchGesture)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            videoPreviewLayer.frame = bounds
            CATransaction.commit()
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            let location = gesture.location(in: self)
            let devicePoint = videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: location)

            manager?.focusAndExpose(at: devicePoint)

            // Show focus indicator
            showFocusIndicator(at: location)
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let manager = manager else { return }

            if gesture.state == .began {
                initialZoom = manager.zoomFactor
            }

            let newZoom = initialZoom * gesture.scale
            manager.setZoom(newZoom)
        }

        private func showFocusIndicator(at point: CGPoint) {
            let indicator = UIView(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
            indicator.center = point
            indicator.layer.borderColor = UIColor.systemYellow.cgColor
            indicator.layer.borderWidth = 2
            indicator.layer.cornerRadius = 40
            indicator.backgroundColor = .clear
            addSubview(indicator)

            UIView.animate(withDuration: 0.3, animations: {
                indicator.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
            }) { _ in
                UIView.animate(withDuration: 0.3, delay: 0.5, options: [], animations: {
                    indicator.alpha = 0
                }) { _ in
                    indicator.removeFromSuperview()
                }
            }
        }
    }
}
#else
struct CameraPreviewView: View {
    @ObservedObject var manager: CameraManager
    var body: some View {
        Rectangle().fill(Color.black).overlay(Text("Camera Preview\n(Not available on macOS)").foregroundColor(.white).multilineTextAlignment(.center))
    }
}
#endif

// MARK: - Overlay Renderer
struct TemplateOverlayView: View {
    var elements: [OverlayElement]
    var lineWidth: CGFloat = 1.5
    var color: Color = .white.opacity(0.7)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(elements) { el in
                    switch el.kind {
                    case .grid:
                        grid(in: geo.size, rows: el.gridRows, cols: el.gridCols)
                            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, dash: [8,4]))
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
        let r = CGRect(x: rect.origin.x * size.width, y: rect.origin.y * size.height, width: rect.size.width * size.width, height: rect.size.height * size.height)
        return Path(roundedRect: r, cornerRadius: 4)
    }

    private func pathForEllipse(_ rect: CGRect, in size: CGSize) -> Path {
        let r = CGRect(x: rect.origin.x * size.width, y: rect.origin.y * size.height, width: rect.size.width * size.width, height: rect.size.height * size.height)
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

// MARK: - Main Tab View
struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            CameraTabView()
                .tabItem {
                    Label("Camera", systemImage: "camera.fill")
                }
                .tag(0)

            TemplateLibraryView()
                .tabItem {
                    Label("Templates", systemImage: "square.grid.2x2.fill")
                }
                .tag(1)

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
                .tag(2)
        }
        .accentColor(.primary)
    }
}

// MARK: - Camera Tab View
struct CameraTabView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var camera = CameraManager()
    @State private var overlayOpacity: Double = 0.8
    @State private var showPhotoPreview = false

    var currentTemplate: PhotoTemplate {
        appState.selectedTemplate ?? SampleTemplates.all[0]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Camera Preview
            CameraPreviewView(manager: camera)
                .ignoresSafeArea()

            // Template Overlay
            if overlayOpacity > 0 {
                TemplateOverlayView(elements: currentTemplate.overlay)
                    .opacity(overlayOpacity)
            }

            // Progress HUD
            if camera.isProcessing {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .transition(.opacity)

                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)

                    Text("Processing...")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(32)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                )
                .transition(.scale.combined(with: .opacity))
            }

            // UI Controls
            VStack {
                // Top Info Bar
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentTemplate.name)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                        Text(currentTemplate.description)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .opacity(0.9)
                    }
                    .foregroundColor(.white)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                            .opacity(0.7)
                    )

                    Spacer()

                    // Camera Toggle Button
                    Button(action: {
                        camera.toggleCamera()
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        #endif
                    }) {
                        Image(systemName: "camera.rotate.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .opacity(0.7)
                            )
                    }
                }
                .padding()

                Spacer()

                // Popular Templates Carousel
                VStack(spacing: 12) {
                    HStack {
                        Text("Popular Templates")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                        Spacer()
                    }
                    .padding(.horizontal, 20)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(SampleTemplates.popular) { template in
                                TemplatePreviewCard(template: template, isSelected: template.id == currentTemplate.id)
                                    .onTapGesture {
                                        selectTemplate(template)
                                    }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 16)

                // Bottom Controls
                HStack(spacing: 20) {
                    // Overlay Opacity Control
                    VStack(spacing: 8) {
                        Image(systemName: overlayOpacity > 0.5 ? "eye.fill" : "eye.slash.fill")
                            .font(.system(size: 16))
                        Slider(value: $overlayOpacity, in: 0...1)
                            .frame(width: 70)
                            .accentColor(.white)
                    }
                    .foregroundColor(.white)
                    .frame(width: 80)

                    Spacer()

                    // Capture Button
                    Button(action: {
                        camera.capture(preset: currentTemplate.preset)
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        #endif
                    }) {
                        ZStack {
                            Circle()
                                .stroke(.white, lineWidth: 5)
                                .frame(width: 75, height: 75)
                            Circle()
                                .fill(.white.opacity(0.3))
                                .frame(width: 60, height: 60)
                        }
                    }

                    Spacer()

                    // Last Photo Preview
                    Group {
                        if let img = camera.latestPhoto {
                            Button {
                                showPhotoPreview.toggle()
                            } label: {
                                #if canImport(UIKit)
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(.white, lineWidth: 2)
                                    )
                                #else
                                Image(nsImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                #endif
                            }
                            .sheet(isPresented: $showPhotoPreview) {
                                PhotoPreviewSheet(image: img)
                            }
                        } else {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.white.opacity(0.2))
                                .frame(width: 60, height: 60)
                        }
                    }
                    .frame(width: 80)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            camera.start()
            camera.activePreset = currentTemplate.preset
        }
        .onDisappear {
            camera.stop()
        }
    }

    private func selectTemplate(_ template: PhotoTemplate) {
        appState.selectedTemplate = template
        camera.activePreset = template.preset
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

// MARK: - Template Preview Card (for bottom carousel)
struct TemplatePreviewCard: View {
    let template: PhotoTemplate
    var isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.15))
                    .frame(width: 80, height: 80)

                TemplateOverlayView(elements: template.overlay, lineWidth: 1, color: .white.opacity(0.8))
                    .frame(width: 70, height: 70)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.white : Color.clear, lineWidth: 2)
            )

            Text(template.name)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: 80)
        }
    }
}

// MARK: - Photo Preview Sheet
struct PhotoPreviewSheet: View {
    #if canImport(UIKit)
    let image: UIImage
    #else
    let image: NSImage
    #endif
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding()
                }

                #if canImport(UIKit)
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                #else
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                #endif

                Text("Saved to Photos")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .padding()
            }
        }
    }
}

// MARK: - Template Library View
struct TemplateLibraryView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedCategory = "All"
    @State private var showTemplateDetail: PhotoTemplate? = nil

    var categories: [String] {
        var cats = Set(appState.templates.map { $0.category })
        cats.insert("All")
        return ["All"] + cats.sorted()
    }

    var filteredTemplates: [PhotoTemplate] {
        if selectedCategory == "All" {
            return appState.templates
        } else {
            return appState.templates.filter { $0.category == selectedCategory }
        }
    }

    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationView {
            ZStack {
                Color(uiColor: UIColor.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Category Filter
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(categories, id: \.self) { category in
                                Button(action: {
                                    selectedCategory = category
                                    #if os(iOS)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    #endif
                                }) {
                                    Text(category)
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundColor(selectedCategory == category ? .white : .primary)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule()
                                                .fill(selectedCategory == category ? Color.black : Color.white)
                                        )
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                    .background(Color(uiColor: UIColor.systemBackground))

                    // Templates Grid
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(filteredTemplates) { template in
                                TemplateLibraryCard(template: template)
                                    .onTapGesture {
                                        showTemplateDetail = template
                                    }
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $showTemplateDetail) { template in
                TemplateDetailView(template: template)
            }
        }
    }
}

// MARK: - Template Library Card
struct TemplateLibraryCard: View {
    @EnvironmentObject var appState: AppState
    let template: PhotoTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Template Preview
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color.black.opacity(0.6), Color.black.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 180)

                TemplateOverlayView(elements: template.overlay, lineWidth: 1.5, color: .white.opacity(0.7))
                    .padding(20)

                // Save Button
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            appState.toggleSaveTemplate(template)
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                        }) {
                            Image(systemName: appState.isSaved(template) ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 18))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Circle().fill(.black.opacity(0.4)))
                        }
                        .padding(12)
                    }
                    Spacer()
                }
            }

            // Template Info
            VStack(alignment: .leading, spacing: 4) {
                Text(template.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)

                Text(template.category)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.06)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
    }
}

// MARK: - Template Detail View
struct TemplateDetailView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    let template: PhotoTemplate

    var body: some View {
        NavigationView {
            ZStack {
                Color(uiColor: UIColor.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Template Preview
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.black.opacity(0.7), Color.black.opacity(0.4)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(height: 400)

                            TemplateOverlayView(elements: template.overlay, lineWidth: 2, color: .white.opacity(0.8))
                                .padding(30)
                        }
                        .padding(.horizontal, 20)

                        // Template Info
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(template.name)
                                        .font(.system(size: 28, weight: .bold, design: .rounded))

                                    Text(template.category)
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 5)
                                        .background(Capsule().fill(Color.black.opacity(0.06)))
                                }

                                Spacer()

                                Button(action: {
                                    appState.toggleSaveTemplate(template)
                                    #if os(iOS)
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    #endif
                                }) {
                                    Image(systemName: appState.isSaved(template) ? "bookmark.fill" : "bookmark")
                                        .font(.system(size: 24))
                                        .foregroundColor(.primary)
                                        .padding(12)
                                        .background(Circle().fill(Color.black.opacity(0.06)))
                                }
                            }

                            Text(template.description)
                                .font(.system(size: 16, weight: .regular, design: .rounded))
                                .foregroundColor(.secondary)
                                .lineSpacing(4)

                            Divider()
                                .padding(.vertical, 8)

                            // Preset Info
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Preset Settings")
                                    .font(.system(size: 18, weight: .semibold, design: .rounded))

                                VStack(spacing: 8) {
                                    if let ev = template.preset.exposureEV {
                                        PresetRow(icon: "sun.max.fill", label: "Exposure", value: String(format: "%.1f EV", ev))
                                    }
                                    if let sat = template.preset.saturation {
                                        PresetRow(icon: "slider.horizontal.3", label: "Saturation", value: String(format: "%.0f%%", sat * 100))
                                    }
                                    if let vib = template.preset.vibrance {
                                        PresetRow(icon: "paintbrush.fill", label: "Vibrance", value: String(format: "%.0f%%", vib * 100))
                                    }
                                    if let cont = template.preset.contrast {
                                        PresetRow(icon: "circle.lefthalf.filled", label: "Contrast", value: String(format: "%.0f%%", cont * 100))
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)

                        // Apply Button
                        Button(action: {
                            appState.selectedTemplate = template
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: "camera.fill")
                                Text("Apply Template")
                                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.black)
                            )
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                    }
                    .padding(.top, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Preset Row
struct PresetRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 24)

            Text(label)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(.primary)

            Spacer()

            Text(value)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.03))
        )
    }
}

// MARK: - Profile View
struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @State private var isEditingProfile = false
    @State private var editedUsername = ""
    @State private var editedBio = ""

    var body: some View {
        NavigationView {
            ZStack {
                Color(uiColor: UIColor.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Profile Header
                        VStack(spacing: 16) {
                            // Avatar
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.black.opacity(0.8), Color.black.opacity(0.5)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 100, height: 100)

                                Image(systemName: "camera.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.white)
                            }

                            VStack(spacing: 8) {
                                Text(appState.userProfile.username)
                                    .font(.system(size: 24, weight: .bold, design: .rounded))

                                Text(appState.userProfile.bio)
                                    .font(.system(size: 14, weight: .regular, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                            }

                            Button(action: {
                                editedUsername = appState.userProfile.username
                                editedBio = appState.userProfile.bio
                                isEditingProfile = true
                            }) {
                                Text("Edit Profile")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .stroke(Color.black.opacity(0.2), lineWidth: 1)
                                    )
                            }
                        }
                        .padding(.vertical, 24)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.white)
                        )
                        .padding(.horizontal, 20)

                        // Stats
                        HStack(spacing: 20) {
                            StatCard(value: "\(appState.templates.count)", label: "Templates")
                            StatCard(value: "\(appState.savedTemplates.count)", label: "Saved")
                        }
                        .padding(.horizontal, 20)

                        // Saved Templates
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Saved Templates")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                Spacer()
                            }
                            .padding(.horizontal, 20)

                            if appState.savedTemplates.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "bookmark")
                                        .font(.system(size: 48))
                                        .foregroundColor(.secondary.opacity(0.3))

                                    Text("No saved templates yet")
                                        .font(.system(size: 16, weight: .medium, design: .rounded))
                                        .foregroundColor(.secondary)

                                    Text("Browse the template library and save your favorites")
                                        .font(.system(size: 14, weight: .regular, design: .rounded))
                                        .foregroundColor(.secondary.opacity(0.7))
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 40)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 60)
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(Color.white)
                                )
                                .padding(.horizontal, 20)
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 16) {
                                        ForEach(appState.savedTemplates) { template in
                                            SavedTemplateCard(template: template)
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                        }
                        .padding(.bottom, 32)
                    }
                    .padding(.top, 20)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $isEditingProfile) {
                EditProfileSheet(
                    username: $editedUsername,
                    bio: $editedBio,
                    onSave: {
                        appState.userProfile.username = editedUsername
                        appState.userProfile.bio = editedBio
                        isEditingProfile = false
                    }
                )
            }
        }
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
        )
    }
}

// MARK: - Saved Template Card
struct SavedTemplateCard: View {
    @EnvironmentObject var appState: AppState
    let template: PhotoTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [Color.black.opacity(0.6), Color.black.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140, height: 140)

                TemplateOverlayView(elements: template.overlay, lineWidth: 1.2, color: .white.opacity(0.7))
                    .frame(width: 130, height: 130)
            }

            Text(template.name)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(width: 140)
        }
        .onTapGesture {
            appState.selectedTemplate = template
        }
    }
}

// MARK: - Edit Profile Sheet
struct EditProfileSheet: View {
    @Binding var username: String
    @Binding var bio: String
    var onSave: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Username")) {
                    TextField("Enter username", text: $username)
                        .font(.system(.body, design: .rounded))
                }

                Section(header: Text("Bio")) {
                    TextEditor(text: $bio)
                        .font(.system(.body, design: .rounded))
                        .frame(height: 100)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - ContentView (keeping for compatibility)
struct ContentView: View {
    var body: some View {
        MainTabView()
    }
}

// MARK: - Extensions
#if canImport(UIKit)
extension UIImage.Orientation {
    var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
#endif
