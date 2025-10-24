//
//  LensPickerTests.swift
//  TemplateCamTests
//
//  Unit tests for LensPicker logic
//

import XCTest
import AVFoundation
@testable import TemplateCam

final class LensPickerTests: XCTestCase {

    var lensPicker: LensPicker!

    override func setUp() {
        super.setUp()
        lensPicker = LensPicker()
    }

    override func tearDown() {
        lensPicker = nil
        super.tearDown()
    }

    func testPickLensWithPerfectMatch() {
        // Mock lens options
        let mockDevice = MockDevice()
        let lens = LensOption(device: mockDevice, kind: .wide, maxZoom: 10.0)

        // Mock probe: target height is 0.5, live height is 0.5 (zoom = 1.0)
        let probes = [LensProbe(lens: lens, subjectHeightLive: 0.5)]

        let result = lensPicker.pickLens(targetHeight: 0.5, probes: probes)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.zoomNeeded, 1.0, accuracy: 0.01)
    }

    func testPickLensRequiresZoom() {
        let mockDevice = MockDevice()
        let lens = LensOption(device: mockDevice, kind: .wide, maxZoom: 10.0)

        // Mock probe: target height is 0.8, live height is 0.4 (zoom = 2.0)
        let probes = [LensProbe(lens: lens, subjectHeightLive: 0.4)]

        let result = lensPicker.pickLens(targetHeight: 0.8, probes: probes)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.zoomNeeded, 2.0, accuracy: 0.01)
    }

    func testPickLensExceedsMaxZoom() {
        let mockDevice = MockDevice()
        let lens = LensOption(device: mockDevice, kind: .wide, maxZoom: 2.0)

        // Mock probe: target height is 0.8, live height is 0.1 (zoom = 8.0 > maxZoom)
        let probes = [LensProbe(lens: lens, subjectHeightLive: 0.1)]

        let result = lensPicker.pickLens(targetHeight: 0.8, probes: probes)

        // Should still return the lens (with instruction to step closer)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.zoomNeeded, 8.0, accuracy: 0.01)
    }

    func testPickBestLensAmongMultiple() {
        let mockDevice1 = MockDevice()
        let mockDevice2 = MockDevice()
        let mockDevice3 = MockDevice()

        let ultrawide = LensOption(device: mockDevice1, kind: .ultrawide, maxZoom: 5.0)
        let wide = LensOption(device: mockDevice2, kind: .wide, maxZoom: 10.0)
        let tele = LensOption(device: mockDevice3, kind: .tele, maxZoom: 15.0)

        // Target height: 0.6
        // Ultrawide: live height 0.3 -> zoom = 2.0
        // Wide: live height 0.5 -> zoom = 1.2 (best, closest to 1.0)
        // Tele: live height 0.7 -> zoom = 0.857
        let probes = [
            LensProbe(lens: ultrawide, subjectHeightLive: 0.3),
            LensProbe(lens: wide, subjectHeightLive: 0.5),
            LensProbe(lens: tele, subjectHeightLive: 0.7)
        ]

        let result = lensPicker.pickLens(targetHeight: 0.6, probes: probes)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.lens.kind, .wide)
    }

    func testShouldReevaluate() {
        // Small difference (< 5%)
        XCTAssertFalse(lensPicker.shouldReevaluate(currentHeight: 0.50, targetHeight: 0.52))

        // Large difference (> 5%)
        XCTAssertTrue(lensPicker.shouldReevaluate(currentHeight: 0.50, targetHeight: 0.60))
    }

    func testDebouncing() {
        let mockDevice = MockDevice()
        let lens = LensOption(device: mockDevice, kind: .wide, maxZoom: 10.0)
        let probes = [LensProbe(lens: lens, subjectHeightLive: 0.5)]

        // First pick
        let result1 = lensPicker.pickLens(targetHeight: 0.5, probes: probes)
        XCTAssertNotNil(result1)

        // Immediate second pick should still work (returns same lens)
        let result2 = lensPicker.pickLens(targetHeight: 0.5, probes: probes)
        XCTAssertNotNil(result2)

        // Results should be similar (debouncing doesn't block, just keeps current lens)
        XCTAssertEqual(result1?.lens.kind, result2?.lens.kind)
    }

    func testReset() {
        lensPicker.reset()
        // After reset, picker should work normally
        let mockDevice = MockDevice()
        let lens = LensOption(device: mockDevice, kind: .wide, maxZoom: 10.0)
        let probes = [LensProbe(lens: lens, subjectHeightLive: 0.5)]

        let result = lensPicker.pickLens(targetHeight: 0.5, probes: probes)
        XCTAssertNotNil(result)
    }
}

// MARK: - Mock Device

class MockDevice: AVCaptureDevice {
    override var uniqueID: String {
        return "mock-device-\(arc4random())"
    }
}
