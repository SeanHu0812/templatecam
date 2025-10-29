//
//  TemplateCamTests.swift
//  TemplateCamTests
//
//  Created by 胡Sean on 2025/10/21.
//

import Testing
import Foundation
import CoreImage
@testable import TemplateCam

struct TemplateCamTests {

    // MARK: - Template JSON Parsing Tests

    @Test func testTemplateJSONParsing() async throws {
        let jsonString = """
        {
          "version": "1.0",
          "templates": [
            {
              "id": "test-template",
              "name": "Test Template",
              "description": "A test template",
              "category": "Test",
              "isPopular": true,
              "thumbnail": "test.jpg",
              "overlay": {
                "elements": [
                  {
                    "kind": "grid",
                    "gridRows": 3,
                    "gridCols": 3
                  }
                ]
              },
              "preset": {
                "name": "Test Preset",
                "exposureEV": 0.5,
                "saturation": 1.1,
                "contrast": 1.05
              }
            }
          ]
        }
        """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let templateData = try decoder.decode(TemplateData.self, from: data)

        #expect(templateData.version == "1.0")
        #expect(templateData.templates.count == 1)
        #expect(templateData.templates[0].name == "Test Template")
        #expect(templateData.templates[0].isPopular == true)
        #expect(templateData.templates[0].overlay.elements.count == 1)
        #expect(templateData.templates[0].preset.exposureEV == 0.5)
    }

    @Test func testOverlayElementParsing() async throws {
        let jsonString = """
        {
          "kind": "ellipse",
          "rect": {
            "x": 0.5,
            "y": 0.5,
            "width": 0.2,
            "height": 0.2
          }
        }
        """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let element = try decoder.decode(JSONOverlayElement.self, from: data)

        #expect(element.kind == "ellipse")
        #expect(element.rect?.x == 0.5)
        #expect(element.rect?.width == 0.2)
    }

    @Test func testPresetParsing() async throws {
        let jsonString = """
        {
          "name": "Test Preset",
          "exposureEV": 0.3,
          "vibrance": 0.2,
          "saturation": 1.05,
          "contrast": 1.03,
          "highlights": 0.1,
          "shadows": -0.1
        }
        """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let preset = try decoder.decode(JSONPreset.self, from: data)

        #expect(preset.name == "Test Preset")
        #expect(preset.exposureEV == 0.3)
        #expect(preset.vibrance == 0.2)
        #expect(preset.highlights == 0.1)
        #expect(preset.shadows == -0.1)
    }

    // MARK: - Filter Application Tests

    @Test func testFilterProcessorExposure() async throws {
        let processor = FilterProcessor.shared
        let testImage = createTestCIImage()

        let preset = Preset(
            name: "Test",
            exposureEV: 0.5
        )

        let result = processor.applyPreset(preset, to: testImage)
        #expect(result.extent.width > 0)
        #expect(result.extent.height > 0)
    }

    @Test func testFilterProcessorSaturation() async throws {
        let processor = FilterProcessor.shared
        let testImage = createTestCIImage()

        let preset = Preset(
            name: "Test",
            saturation: 1.2
        )

        let result = processor.applyPreset(preset, to: testImage)
        #expect(result.extent.width > 0)
    }

    @Test func testFilterProcessorContrast() async throws {
        let processor = FilterProcessor.shared
        let testImage = createTestCIImage()

        let preset = Preset(
            name: "Test",
            contrast: 1.1
        )

        let result = processor.applyPreset(preset, to: testImage)
        #expect(result.extent.width > 0)
    }

    @Test func testFilterProcessorVibrance() async throws {
        let processor = FilterProcessor.shared
        let testImage = createTestCIImage()

        let preset = Preset(
            name: "Test",
            vibrance: 0.3
        )

        let result = processor.applyPreset(preset, to: testImage)
        #expect(result.extent.width > 0)
    }

    @Test func testFilterProcessorMultipleFilters() async throws {
        let processor = FilterProcessor.shared
        let testImage = createTestCIImage()

        let preset = Preset(
            name: "Test",
            exposureEV: 0.2,
            vibrance: 0.2,
            saturation: 1.05,
            contrast: 1.03
        )

        let result = processor.applyPreset(preset, to: testImage)
        #expect(result.extent.width > 0)
        #expect(result.extent.height > 0)
    }

    // MARK: - Template Loader Tests

    @Test func testTemplateLoaderFallback() async throws {
        let loader = TemplateLoader.shared
        let templates = loader.loadTemplates()

        // Should fallback to hardcoded templates if JSON not found
        #expect(templates.count > 0)
    }

    // MARK: - Persistence Tests

    @Test func testPersistenceManager() async throws {
        let manager = PersistenceManager.shared

        let testProfile = UserProfile(
            username: "TestUser",
            bio: "Test Bio",
            savedTemplateIds: []
        )

        manager.saveUserProfile(testProfile)

        if let loadedProfile = manager.loadUserProfile() {
            #expect(loadedProfile.username == "TestUser")
            #expect(loadedProfile.bio == "Test Bio")
        }
    }

    @Test func testSavedTemplateIdsPersistence() async throws {
        let manager = PersistenceManager.shared

        let testIds = [UUID(), UUID(), UUID()]
        manager.saveSavedTemplateIds(testIds)

        let loadedIds = manager.loadSavedTemplateIds()
        #expect(loadedIds.count == 3)
        #expect(loadedIds == testIds)
    }

    // MARK: - Model Tests

    @Test func testPhotoTemplateEquality() async throws {
        let template1 = PhotoTemplate(
            id: UUID(),
            name: "Test",
            description: "Test",
            category: "Test",
            overlay: [],
            preset: Preset(name: "Test"),
            isPopular: false
        )

        let template2 = PhotoTemplate(
            id: template1.id,
            name: "Different",
            description: "Different",
            category: "Different",
            overlay: [],
            preset: Preset(name: "Different"),
            isPopular: true
        )

        #expect(template1 == template2) // Should be equal because IDs match
    }

    @Test func testPresetCodable() async throws {
        let preset = Preset(
            name: "Test",
            exposureEV: 0.5,
            vibrance: 0.2,
            saturation: 1.1,
            contrast: 1.05
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(preset)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Preset.self, from: data)

        #expect(decoded.name == preset.name)
        #expect(decoded.exposureEV == preset.exposureEV)
        #expect(decoded.vibrance == preset.vibrance)
    }

    // MARK: - Helper Methods

    private func createTestCIImage() -> CIImage {
        let size = CGSize(width: 100, height: 100)
        let color = CIColor(red: 0.5, green: 0.5, blue: 0.5)
        let filter = CIFilter(name: "CIConstantColorGenerator")!
        filter.setValue(color, forKey: kCIInputColorKey)
        let image = filter.outputImage!
        return image.cropped(to: CGRect(origin: .zero, size: size))
    }
}
