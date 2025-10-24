//
//  TemplateStore.swift
//  TemplateCam
//
//  Template persistence and loading
//

import Foundation

class TemplateStore {
    static let shared = TemplateStore()

    private let documentsDirectory: URL
    private let templatesDirectory: URL

    private init() {
        // Get documents directory
        documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        templatesDirectory = documentsDirectory.appendingPathComponent("Templates", isDirectory: true)

        // Create templates directory if needed
        if !FileManager.default.fileExists(atPath: templatesDirectory.path) {
            try? FileManager.default.createDirectory(at: templatesDirectory, withIntermediateDirectories: true)
        }
    }

    // MARK: - Load

    /// Load all templates from documents directory
    func loadAll() -> [Template] {
        var templates: [Template] = []

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: templatesDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return templates
        }

        for fileURL in files where fileURL.pathExtension == "json" {
            if let template = load(from: fileURL) {
                templates.append(template)
            }
        }

        return templates
    }

    /// Load a specific template by ID
    func loadTemplate(id: String) -> Template? {
        let fileURL = templatesDirectory.appendingPathComponent("\(id).json")
        return load(from: fileURL)
    }

    /// Load the bundled seed template
    func loadSeed() -> Template? {
        // Try to load from bundle
        if let bundleURL = Bundle.main.url(forResource: "seed_template", withExtension: "json", subdirectory: "Resources/Templates") {
            return load(from: bundleURL)
        }

        // Fallback to default programmatic template
        Logger.log("Could not load seed template from bundle, using default")
        return Template.defaultSeed()
    }

    private func load(from url: URL) -> Template? {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            var template = try decoder.decode(Template.self, from: data)
            template = template.validated()
            return template
        } catch {
            Logger.log("Failed to load template from \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    // MARK: - Save

    /// Save a template to documents directory
    func save(_ template: Template) -> Bool {
        let validated = template.validated()
        let fileURL = templatesDirectory.appendingPathComponent("\(validated.id).json")

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(validated)
            try data.write(to: fileURL)
            Logger.log("Template saved: \(validated.id)")
            return true
        } catch {
            Logger.log("Failed to save template \(validated.id): \(error)")
            return false
        }
    }

    /// Delete a template
    func delete(id: String) -> Bool {
        let fileURL = templatesDirectory.appendingPathComponent("\(id).json")

        do {
            try FileManager.default.removeItem(at: fileURL)
            Logger.log("Template deleted: \(id)")
            return true
        } catch {
            Logger.log("Failed to delete template \(id): \(error)")
            return false
        }
    }

    // MARK: - Helpers

    /// Get file URL for a template
    func fileURL(for templateID: String) -> URL {
        return templatesDirectory.appendingPathComponent("\(templateID).json")
    }

    /// Check if a template exists
    func exists(id: String) -> Bool {
        let fileURL = templatesDirectory.appendingPathComponent("\(id).json")
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
}
