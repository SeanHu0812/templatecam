//
//  TemplateTests.swift
//  TemplateCamTests
//
//  Unit tests for Template data model
//

import XCTest
@testable import TemplateCam

final class TemplateTests: XCTestCase {

    func testTemplateDefaultSeed() {
        let template = Template.defaultSeed()

        XCTAssertEqual(template.id, "seed_001")
        XCTAssertEqual(template.v, 1)
        XCTAssertEqual(template.subject.targetBoxHeightPct, 0.68)
        XCTAssertEqual(template.cameraTargets.zoomFactor, 1.0)
    }

    func testTemplateCodable() throws {
        let original = Template.defaultSeed()

        // Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Template.self, from: data)

        // Verify
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.v, original.v)
        XCTAssertEqual(decoded.subject.targetBoxHeightPct, original.subject.targetBoxHeightPct)
        XCTAssertEqual(decoded.cameraTargets.tone.contrast, original.cameraTargets.tone.contrast)
    }

    func testTemplateValidation() {
        var template = Template.defaultSeed()

        // Set out-of-range values
        template.cameraTargets.tone.exposureEV = 5.0  // > 1.0
        template.cameraTargets.tone.contrast = 0.5    // < 0.8
        template.cameraTargets.tone.saturation = 2.0  // > 1.3
        template.cameraTargets.wb.temperature = 10000 // > 7500
        template.cameraTargets.wb.tint = 50           // > 20

        // Validate
        let validated = template.validated()

        // Check clamping
        XCTAssertEqual(validated.cameraTargets.tone.exposureEV, 1.0)
        XCTAssertEqual(validated.cameraTargets.tone.contrast, 0.8)
        XCTAssertEqual(validated.cameraTargets.tone.saturation, 1.3)
        XCTAssertEqual(validated.cameraTargets.wb.temperature, 7500)
        XCTAssertEqual(validated.cameraTargets.wb.tint, 20)
    }

    func testToneClamping() {
        var tone = Template.CameraTargets.Tone(
            exposureEV: -2.0,
            contrast: 2.0,
            highlights: 1.0,
            shadows: -1.0,
            saturation: 0.5,
            vibrance: 1.0,
            sharpness: 1.0
        )

        // Clamp individual values
        tone.exposureEV = tone.exposureEV.clamped(to: -1.0...1.0)
        tone.contrast = tone.contrast.clamped(to: 0.8...1.3)
        tone.highlights = tone.highlights.clamped(to: -0.3...0.3)
        tone.shadows = tone.shadows.clamped(to: -0.3...0.3)
        tone.saturation = tone.saturation.clamped(to: 0.8...1.3)
        tone.vibrance = tone.vibrance.clamped(to: 0.0...0.5)
        tone.sharpness = tone.sharpness.clamped(to: 0.0...0.3)

        XCTAssertEqual(tone.exposureEV, -1.0)
        XCTAssertEqual(tone.contrast, 1.3)
        XCTAssertEqual(tone.highlights, 0.3)
        XCTAssertEqual(tone.shadows, -0.3)
        XCTAssertEqual(tone.saturation, 0.8)
        XCTAssertEqual(tone.vibrance, 0.5)
        XCTAssertEqual(tone.sharpness, 0.3)
    }

    func testBBoxNormalization() {
        let bbox = Template.Subject.BBox(x: 0.25, y: 0.25, w: 0.5, h: 0.5)

        XCTAssertTrue(bbox.x >= 0 && bbox.x <= 1)
        XCTAssertTrue(bbox.y >= 0 && bbox.y <= 1)
        XCTAssertTrue(bbox.w >= 0 && bbox.w <= 1)
        XCTAssertTrue(bbox.h >= 0 && bbox.h <= 1)
    }

    func testKeybonesStructure() {
        let template = Template.defaultSeed()

        // Check keybones format
        for bone in template.subject.keybones {
            XCTAssertEqual(bone.count, 2, "Each bone should have exactly 2 joints")
        }
    }

    func testWhiteBalanceRange() {
        var wb = Template.CameraTargets.WhiteBalance(temperature: 2000, tint: -50)

        // Clamp
        wb.temperature = wb.temperature.clamped(to: 3000...7500)
        wb.tint = wb.tint.clamped(to: -20...20)

        XCTAssertEqual(wb.temperature, 3000)
        XCTAssertEqual(wb.tint, -20)
    }
}
