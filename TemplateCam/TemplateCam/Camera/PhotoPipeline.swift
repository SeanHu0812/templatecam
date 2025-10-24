//
//  PhotoPipeline.swift
//  TemplateCam
//
//  Core Image processing pipeline for preview and post-capture
//

import CoreImage
import CoreVideo
import UIKit

class PhotoPipeline {

    // MARK: - Properties

    private let context: CIContext
    private var filterChain: [CIFilter] = []

    // Cached filters for reuse
    private let exposureFilter = CIFilter(name: "CIExposureAdjust")!
    private let vibranceFilter = CIFilter(name: "CIVibrance")!
    private let colorControlsFilter = CIFilter(name: "CIColorControls")!
    private let toneCurveFilter = CIFilter(name: "CIToneCurve")!
    private let unsharpMaskFilter = CIFilter(name: "CIUnsharpMask")!

    // MARK: - Initialization

    init() {
        // Create Metal-backed context for best performance
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: [
                .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                .cacheIntermediates: false
            ])
        } else {
            context = CIContext(options: [
                .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
            ])
        }
    }

    // MARK: - Apply to Preview (Pixel Buffer)

    /// Apply tone adjustments to a preview pixel buffer
    /// - Parameters:
    ///   - pixelBuffer: Input CVPixelBuffer from video output
    ///   - tone: Tone settings
    /// - Returns: Processed CIImage
    func applyPreview(_ pixelBuffer: CVPixelBuffer, tone: Template.CameraTargets.Tone) -> CIImage {
        let inputImage = CIImage(cvPixelBuffer: pixelBuffer)
        return applyTonePipeline(to: inputImage, tone: tone)
    }

    // MARK: - Apply to Photo (CIImage)

    /// Apply tone adjustments to a captured photo
    /// - Parameters:
    ///   - image: Input CIImage
    ///   - tone: Tone settings
    /// - Returns: Processed CIImage
    func applyPhoto(_ image: CIImage, tone: Template.CameraTargets.Tone) -> CIImage {
        return applyTonePipeline(to: image, tone: tone)
    }

    // MARK: - Tone Pipeline

    private func applyTonePipeline(to image: CIImage, tone: Template.CameraTargets.Tone) -> CIImage {
        var output = image

        // 1. Exposure Adjust
        if tone.exposureEV != 0 {
            exposureFilter.setValue(output, forKey: kCIInputImageKey)
            exposureFilter.setValue(tone.exposureEV, forKey: kCIInputEVKey)
            if let result = exposureFilter.outputImage {
                output = result
            }
        }

        // 2. Vibrance
        if tone.vibrance != 0 {
            vibranceFilter.setValue(output, forKey: kCIInputImageKey)
            vibranceFilter.setValue(tone.vibrance, forKey: "inputAmount")
            if let result = vibranceFilter.outputImage {
                output = result
            }
        }

        // 3. Color Controls (Saturation & Contrast)
        let needsColorControls = tone.saturation != 1.0 || tone.contrast != 1.0
        if needsColorControls {
            colorControlsFilter.setValue(output, forKey: kCIInputImageKey)
            colorControlsFilter.setValue(tone.saturation, forKey: kCIInputSaturationKey)
            colorControlsFilter.setValue(tone.contrast, forKey: kCIInputContrastKey)
            colorControlsFilter.setValue(1.0, forKey: kCIInputBrightnessKey)
            if let result = colorControlsFilter.outputImage {
                output = result
            }
        }

        // 4. Tone Curve for Highlights/Shadows
        let needsToneCurve = tone.highlights != 0 || tone.shadows != 0
        if needsToneCurve {
            output = applyToneCurve(to: output, highlights: tone.highlights, shadows: tone.shadows)
        }

        // 5. Unsharp Mask (Sharpness)
        if tone.sharpness > 0 {
            unsharpMaskFilter.setValue(output, forKey: kCIInputImageKey)
            unsharpMaskFilter.setValue(1.0, forKey: kCIInputRadiusKey)
            unsharpMaskFilter.setValue(tone.sharpness * 2.0, forKey: kCIInputIntensityKey)  // Scale 0-0.3 to 0-0.6
            if let result = unsharpMaskFilter.outputImage {
                output = result
            }
        }

        return output
    }

    // MARK: - Tone Curve

    private func applyToneCurve(to image: CIImage, highlights: CGFloat, shadows: CGFloat) -> CIImage {
        // Create 5-point tone curve
        // Points: black(0,0), shadows(0.25), mid(0.5), highlights(0.75), white(1,1)

        let shadowPoint = CGPoint(x: 0.25, y: 0.25 + shadows * 0.5)
        let midPoint = CGPoint(x: 0.5, y: 0.5)
        let highlightPoint = CGPoint(x: 0.75, y: 0.75 + highlights * 0.5)

        toneCurveFilter.setValue(image, forKey: kCIInputImageKey)
        toneCurveFilter.setValue(CIVector(x: 0, y: 0), forKey: "inputPoint0")
        toneCurveFilter.setValue(CIVector(cgPoint: shadowPoint), forKey: "inputPoint1")
        toneCurveFilter.setValue(CIVector(cgPoint: midPoint), forKey: "inputPoint2")
        toneCurveFilter.setValue(CIVector(cgPoint: highlightPoint), forKey: "inputPoint3")
        toneCurveFilter.setValue(CIVector(x: 1, y: 1), forKey: "inputPoint4")

        return toneCurveFilter.outputImage ?? image
    }

    // MARK: - Render to UIImage

    /// Render CIImage to UIImage
    /// - Parameter ciImage: Input CIImage
    /// - Returns: UIImage or nil
    func renderToUIImage(_ ciImage: CIImage) -> UIImage? {
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
    }

    /// Render CIImage to CVPixelBuffer (for preview layer)
    /// - Parameters:
    ///   - ciImage: Input CIImage
    ///   - pixelBuffer: Output CVPixelBuffer
    func renderToPixelBuffer(_ ciImage: CIImage, pixelBuffer: CVPixelBuffer) {
        context.render(ciImage, to: pixelBuffer)
    }
}
