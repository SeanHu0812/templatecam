//
//  Template.swift
//  TemplateCam
//
//  Template data model for camera framing and settings
//

import Foundation
import CoreGraphics

// MARK: - Template (v1 JSON spec)

struct Template: Codable {
    let id: String
    let v: Int
    let frame: Frame
    let subject: Subject
    let background: Background
    let cameraTargets: CameraTargets

    struct Frame: Codable {
        let aspectRatio: String // "device" or specific ratio
    }

    struct Subject: Codable {
        let bbox: BBox
        let targetBoxHeightPct: CGFloat
        let keybones: [[String]]  // Array of bone pairs e.g. ["left_shoulder", "right_shoulder"]

        struct BBox: Codable {
            let x: CGFloat
            let y: CGFloat
            let w: CGFloat
            let h: CGFloat
        }
    }

    struct Background: Codable {
        let horizonY: CGFloat?
        let dominantLines: [[[CGFloat]]]  // Array of line segments [[[x1,y1],[x2,y2]]]
    }

    struct CameraTargets: Codable {
        let preferLenses: [String]
        let zoomFactor: CGFloat
        let flash: String
        let exposureBiasEV: CGFloat
        let wb: WhiteBalance
        let tone: Tone

        struct WhiteBalance: Codable {
            let temperature: CGFloat
            let tint: CGFloat
        }

        struct Tone: Codable {
            var exposureEV: CGFloat
            var contrast: CGFloat
            var highlights: CGFloat
            var shadows: CGFloat
            var saturation: CGFloat
            var vibrance: CGFloat
            var sharpness: CGFloat
        }
    }
}

// MARK: - Template Extensions

extension Template {
    /// Default seed template for testing
    static func defaultSeed() -> Template {
        return Template(
            id: "seed_001",
            v: 1,
            frame: Frame(aspectRatio: "device"),
            subject: Subject(
                bbox: Subject.BBox(x: 0.28, y: 0.12, w: 0.44, h: 0.68),
                targetBoxHeightPct: 0.68,
                keybones: [
                    ["left_shoulder", "right_shoulder"],
                    ["right_shoulder", "right_hip"],
                    ["left_shoulder", "left_hip"],
                    ["right_hip", "right_knee"],
                    ["left_hip", "left_knee"]
                ]
            ),
            background: Background(
                horizonY: 0.60,
                dominantLines: [[[0.1, 0.6], [0.9, 0.6]]]
            ),
            cameraTargets: CameraTargets(
                preferLenses: ["wide", "ultrawide", "tele"],
                zoomFactor: 1.0,
                flash: "off",
                exposureBiasEV: 0.0,
                wb: CameraTargets.WhiteBalance(temperature: 5500, tint: 0),
                tone: CameraTargets.Tone(
                    exposureEV: 0.0,
                    contrast: 1.0,
                    highlights: 0.0,
                    shadows: 0.0,
                    saturation: 1.0,
                    vibrance: 0.0,
                    sharpness: 0.0
                )
            )
        )
    }

    /// Validate template values and clamp to acceptable ranges
    func validated() -> Template {
        var template = self

        // Clamp tone values
        template.cameraTargets.tone.exposureEV = template.cameraTargets.tone.exposureEV.clamped(to: -1.0...1.0)
        template.cameraTargets.tone.contrast = template.cameraTargets.tone.contrast.clamped(to: 0.8...1.3)
        template.cameraTargets.tone.highlights = template.cameraTargets.tone.highlights.clamped(to: -0.3...0.3)
        template.cameraTargets.tone.shadows = template.cameraTargets.tone.shadows.clamped(to: -0.3...0.3)
        template.cameraTargets.tone.saturation = template.cameraTargets.tone.saturation.clamped(to: 0.8...1.3)
        template.cameraTargets.tone.vibrance = template.cameraTargets.tone.vibrance.clamped(to: 0.0...0.5)
        template.cameraTargets.tone.sharpness = template.cameraTargets.tone.sharpness.clamped(to: 0.0...0.3)

        // Clamp WB values
        template.cameraTargets.wb.temperature = template.cameraTargets.wb.temperature.clamped(to: 3000...7500)
        template.cameraTargets.wb.tint = template.cameraTargets.wb.tint.clamped(to: -20...20)

        // Clamp exposure bias
        template.cameraTargets.exposureBiasEV = template.cameraTargets.exposureBiasEV.clamped(to: -1.0...1.0)

        return template
    }
}

// MARK: - Comparable Extension

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}
