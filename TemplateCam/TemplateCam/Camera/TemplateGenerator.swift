//
//  TemplateGenerator.swift
//  TemplateCam
//
//  Generate template from reference photo using Vision
//

import UIKit
import Vision
import CoreImage
import ImageIO

class TemplateGenerator {

    // MARK: - Generate Template

    /// Generate a template from a reference photo
    /// - Parameter image: Reference photo containing subject
    /// - Parameter completion: Completion with generated template or error
    static func generateTemplate(from image: UIImage, completion: @escaping (Result<Template, Error>) -> Void) {
        guard let ciImage = CIImage(image: image) else {
            completion(.failure(TemplateError.invalidImage))
            return
        }

        let imageSize = ciImage.extent.size

        // Run Vision requests
        let bodyPoseRequest = VNDetectHumanBodyPoseRequest()
        let rectanglesRequest = VNDetectHumanRectanglesRequest()

        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([bodyPoseRequest, rectanglesRequest])

                // Extract pose and rectangle
                guard let poseObservation = bodyPoseRequest.results?.first else {
                    completion(.failure(TemplateError.noPoseDetected))
                    return
                }

                // Get subject bounding box
                let bbox = rectanglesRequest.results?.first?.boundingBox ?? poseObservation.boundingBox

                // Normalize bbox to 0-1 space (Vision returns bottom-left origin)
                let normalizedBBox = Template.Subject.BBox(
                    x: bbox.origin.x,
                    y: bbox.origin.y,
                    w: bbox.size.width,
                    h: bbox.size.height
                )

                // Extract keybones from pose
                let keybones = extractKeybones(from: poseObservation)

                // Detect horizon
                let horizonY = detectHorizon(in: ciImage)

                // Estimate WB from image
                let (temperature, tint) = estimateWhiteBalance(from: image)

                // Estimate tone from image stats
                let tone = estimateTone(from: image)

                // Create template
                let template = Template(
                    id: "template_\(UUID().uuidString.prefix(8))",
                    v: 1,
                    frame: Template.Frame(aspectRatio: "device"),
                    subject: Template.Subject(
                        bbox: normalizedBBox,
                        targetBoxHeightPct: bbox.size.height,
                        keybones: keybones
                    ),
                    background: Template.Background(
                        horizonY: horizonY,
                        dominantLines: horizonY != nil ? [[[0.1, horizonY!], [0.9, horizonY!]]] : []
                    ),
                    cameraTargets: Template.CameraTargets(
                        preferLenses: ["wide", "ultrawide", "tele"],
                        zoomFactor: 1.0,
                        flash: "off",
                        exposureBiasEV: 0.0,
                        wb: Template.CameraTargets.WhiteBalance(
                            temperature: temperature,
                            tint: tint
                        ),
                        tone: tone
                    )
                )

                DispatchQueue.main.async {
                    completion(.success(template.validated()))
                }

            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Extract Keybones

    private static func extractKeybones(from observation: VNHumanBodyPoseObservation) -> [[String]] {
        // Key joints for framing (simplified skeleton)
        let keyJoints: [VNHumanBodyPoseObservation.JointName] = [
            .leftShoulder, .rightShoulder,
            .leftHip, .rightHip,
            .leftKnee, .rightKnee
        ]

        // Check which joints are available with sufficient confidence
        var availableJoints = Set<String>()
        for joint in keyJoints {
            if let point = try? observation.recognizedPoint(joint), point.confidence > 0.3 {
                availableJoints.insert(joint.rawValue.rawValue)
            }
        }

        // Define keybones (only include if both endpoints exist)
        var keybones: [[String]] = []

        let bonePairs: [(String, String)] = [
            ("left_shoulder", "right_shoulder"),
            ("right_shoulder", "right_hip"),
            ("left_shoulder", "left_hip"),
            ("right_hip", "right_knee"),
            ("left_hip", "left_knee")
        ]

        for (start, end) in bonePairs {
            if availableJoints.contains(start) && availableJoints.contains(end) {
                keybones.append([start, end])
            }
        }

        // Fallback to basic skeleton if no bones detected
        if keybones.isEmpty {
            keybones = [
                ["left_shoulder", "right_shoulder"],
                ["right_shoulder", "right_hip"],
                ["left_shoulder", "left_hip"]
            ]
        }

        return keybones
    }

    // MARK: - Detect Horizon

    private static func detectHorizon(in image: CIImage) -> CGFloat? {
        // Simple horizon detection using edge detection
        // Look for strong horizontal lines in the middle third of the image

        let context = CIContext()
        let imageSize = image.extent.size

        // Apply edge detection
        guard let edgeFilter = CIFilter(name: "CIEdges") else { return nil }
        edgeFilter.setValue(image, forKey: kCIInputImageKey)
        edgeFilter.setValue(1.0, forKey: kCIInputIntensityKey)

        guard let edgeImage = edgeFilter.outputImage else { return nil }

        // Sample horizontal strips in the middle region (0.3 to 0.7)
        let stripHeight: CGFloat = 10
        var maxEdgeStrength: CGFloat = 0
        var horizonY: CGFloat = 0.5

        for y in stride(from: imageSize.height * 0.3, to: imageSize.height * 0.7, by: stripHeight) {
            let stripRect = CGRect(x: 0, y: y, width: imageSize.width, height: stripHeight)
            if let cgImage = context.createCGImage(edgeImage, from: stripRect) {
                // Estimate edge strength (simplified)
                let edgeStrength = CGFloat(cgImage.width * cgImage.height)
                if edgeStrength > maxEdgeStrength {
                    maxEdgeStrength = edgeStrength
                    horizonY = y / imageSize.height
                }
            }
        }

        // Only return horizon if edge strength is significant
        return maxEdgeStrength > 1000 ? horizonY : nil
    }

    // MARK: - Estimate White Balance

    private static func estimateWhiteBalance(from image: UIImage) -> (temperature: CGFloat, tint: CGFloat) {
        // Simple gray-world assumption
        guard let ciImage = CIImage(image: image) else {
            return (5500, 0)  // Default daylight
        }

        let context = CIContext()
        let extent = ciImage.extent

        // Sample center region
        let sampleRect = CGRect(
            x: extent.midX - extent.width * 0.1,
            y: extent.midY - extent.height * 0.1,
            width: extent.width * 0.2,
            height: extent.height * 0.2
        )

        guard let filter = CIFilter(name: "CIAreaAverage") else {
            return (5500, 0)
        }

        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: sampleRect), forKey: kCIInputExtentKey)

        guard let outputImage = filter.outputImage,
              let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return (5500, 0)
        }

        // Extract average RGB
        var bitmap = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let bitmapContext = CGContext(
            data: &bitmap,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return (5500, 0)
        }

        bitmapContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        let r = CGFloat(bitmap[0]) / 255.0
        let g = CGFloat(bitmap[1]) / 255.0
        let b = CGFloat(bitmap[2]) / 255.0

        // Estimate temperature from R/B ratio
        let rbRatio = r / max(b, 0.01)
        let temperature: CGFloat
        if rbRatio > 1.2 {
            temperature = 6500  // Warm
        } else if rbRatio < 0.8 {
            temperature = 4500  // Cool
        } else {
            temperature = 5500  // Neutral
        }

        // Estimate tint from G deviation
        let grayAverage = (r + b) / 2.0
        let tint = (g - grayAverage) * 20.0  // Scale to -20...+20 range

        return (temperature, tint.clamped(to: -20...20))
    }

    // MARK: - Estimate Tone

    private static func estimateTone(from image: UIImage) -> Template.CameraTargets.Tone {
        // Analyze image histogram to suggest default tone adjustments
        guard let ciImage = CIImage(image: image) else {
            return Template.CameraTargets.Tone(
                exposureEV: 0.0,
                contrast: 1.0,
                highlights: 0.0,
                shadows: 0.0,
                saturation: 1.0,
                vibrance: 0.0,
                sharpness: 0.0
            )
        }

        let context = CIContext()

        // Get average luminance
        guard let filter = CIFilter(name: "CIAreaAverage") else {
            return Template.CameraTargets.Tone(
                exposureEV: 0.0, contrast: 1.0, highlights: 0.0,
                shadows: 0.0, saturation: 1.0, vibrance: 0.0, sharpness: 0.0
            )
        }

        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: ciImage.extent), forKey: kCIInputExtentKey)

        guard let outputImage = filter.outputImage,
              let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return Template.CameraTargets.Tone(
                exposureEV: 0.0, contrast: 1.0, highlights: 0.0,
                shadows: 0.0, saturation: 1.0, vibrance: 0.0, sharpness: 0.0
            )
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let bitmapContext = CGContext(
            data: &bitmap,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return Template.CameraTargets.Tone(
                exposureEV: 0.0, contrast: 1.0, highlights: 0.0,
                shadows: 0.0, saturation: 1.0, vibrance: 0.0, sharpness: 0.0
            )
        }

        bitmapContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        let luminance = (0.299 * CGFloat(bitmap[0]) + 0.587 * CGFloat(bitmap[1]) + 0.114 * CGFloat(bitmap[2])) / 255.0

        // Suggest adjustments based on luminance
        let exposureEV: CGFloat = luminance < 0.4 ? 0.2 : (luminance > 0.6 ? -0.1 : 0.0)

        return Template.CameraTargets.Tone(
            exposureEV: exposureEV,
            contrast: 1.05,
            highlights: -0.05,
            shadows: 0.05,
            saturation: 1.02,
            vibrance: 0.05,
            sharpness: 0.1
        )
    }
}

// MARK: - Errors

enum TemplateError: LocalizedError {
    case invalidImage
    case noPoseDetected
    case processingFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Invalid image provided"
        case .noPoseDetected:
            return "No person detected in the image"
        case .processingFailed:
            return "Failed to process image"
        }
    }
}
