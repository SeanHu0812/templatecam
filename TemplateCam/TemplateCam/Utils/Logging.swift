//
//  Logging.swift
//  TemplateCam
//
//  Simple logging utility for camera operations
//

import Foundation

struct Logger {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    /// Log a message with timestamp
    static func log(_ message: String, category: String = "TemplateCam") {
        let timestamp = dateFormatter.string(from: Date())
        print("[\(timestamp)] [\(category)] \(message)")
    }

    /// Log lens switch events
    static func logLensSwitch(from: String, to: String, zoom: CGFloat) {
        log("Lens switch: \(from) → \(to) @ \(String(format: "%.2fx", zoom))", category: "LensPicker")
    }

    /// Log exposure/WB lock events
    static func logExposureLock(ev: Float, temperature: CGFloat, tint: CGFloat) {
        log("Exposure locked: EV=\(String(format: "%.2f", ev)), Temp=\(Int(temperature))K, Tint=\(Int(tint))", category: "ExposureWB")
    }

    /// Log Vision detection results
    static func logVisionDetection(confidence: Float, subjectHeight: CGFloat) {
        log("Vision detection: confidence=\(String(format: "%.2f", confidence)), height=\(String(format: "%.3f", subjectHeight))", category: "Vision")
    }

    /// Log zoom changes
    static func logZoom(_ factor: CGFloat, lens: String) {
        log("Zoom set: \(String(format: "%.2fx", factor)) on \(lens)", category: "CaptureSession")
    }

    /// Log coaching instructions
    static func logCoaching(_ instruction: String, score: CGFloat) {
        log("Coaching: \(instruction) (score=\(String(format: "%.2f", score)))", category: "Coaching")
    }

    /// Log errors
    static func logError(_ error: Error, context: String = "") {
        let contextStr = context.isEmpty ? "" : " [\(context)]"
        log("Error\(contextStr): \(error.localizedDescription)", category: "Error")
    }
}
