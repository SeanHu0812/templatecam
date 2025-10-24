//
//  LensPicker.swift
//  TemplateCam
//
//  Auto lens selection based on subject height matching
//

import Foundation
import CoreGraphics

// MARK: - Probe Result

struct LensProbe {
    let lens: LensOption
    let subjectHeightLive: CGFloat  // Measured height at zoom=1.0
}

// MARK: - Lens Picker

class LensPicker {

    // MARK: - Properties

    private var lastPickTime: Date?
    private var lastPickedLens: LensOption?
    private let debounceInterval: TimeInterval = 1.5  // Minimum 1.5s between picks

    // MARK: - Pick Lens

    /// Pick the best lens based on target height and live measurements
    /// - Parameters:
    ///   - targetHeight: Target subject height (0-1 normalized)
    ///   - probes: Array of probe results from available lenses
    /// - Returns: Selected lens and zoom factor needed
    func pickLens(targetHeight: CGFloat, probes: [LensProbe]) -> (lens: LensOption, zoomNeeded: CGFloat)? {
        guard !probes.isEmpty else {
            Logger.log("No lens probes available", category: "LensPicker")
            return nil
        }

        // Check debounce
        if let lastTime = lastPickTime {
            let elapsed = Date().timeIntervalSince(lastTime)
            if elapsed < debounceInterval {
                // Still in debounce period, keep current lens if available
                if let current = lastPickedLens,
                   let currentProbe = probes.first(where: { $0.lens.device == current.device }) {
                    let zoomNeeded = targetHeight / currentProbe.subjectHeightLive
                    return (current, zoomNeeded)
                }
            }
        }

        // Evaluate each lens
        var candidates: [(lens: LensOption, zoomNeeded: CGFloat, score: CGFloat)] = []

        for probe in probes {
            let zoomNeeded = targetHeight / max(probe.subjectHeightLive, 0.001)

            // Check if zoom is achievable
            if zoomNeeded > probe.lens.maxZoom {
                // Can't achieve target with this lens
                continue
            }

            // Score: prefer zoom closest to 1.0 (less digital zoom)
            let score = abs(zoomNeeded - 1.0)

            candidates.append((lens: probe.lens, zoomNeeded: zoomNeeded, score: score))
        }

        // Sort by score (lower is better)
        candidates.sort { $0.score < $1.score }

        guard let best = candidates.first else {
            // No lens can achieve target without exceeding maxZoom
            // Pick the one requiring smallest zoom and instruct user to step closer
            let minZoomProbe = probes.min { p1, p2 in
                let z1 = targetHeight / p1.subjectHeightLive
                let z2 = targetHeight / p2.subjectHeightLive
                return z1 < z2
            }

            if let probe = minZoomProbe {
                let zoomNeeded = targetHeight / probe.subjectHeightLive
                Logger.log("All lenses exceed maxZoom; using \(probe.lens.kind.rawValue) @ \(String(format: "%.2fx", zoomNeeded))", category: "LensPicker")
                lastPickTime = Date()
                lastPickedLens = probe.lens
                return (probe.lens, zoomNeeded)
            }

            return nil
        }

        // Check tolerance: if current lens is already within 20% of optimal, keep it
        if let current = lastPickedLens,
           let currentCandidate = candidates.first(where: { $0.lens.device == current.device }) {
            if currentCandidate.score <= 0.2 {
                // Current lens is good enough, avoid switching
                Logger.log("Keeping current lens \(current.kind.rawValue) (score: \(String(format: "%.3f", currentCandidate.score)))", category: "LensPicker")
                return (current, currentCandidate.zoomNeeded)
            }
        }

        // Pick best candidate
        Logger.log("Selected \(best.lens.kind.rawValue) @ \(String(format: "%.2fx", best.zoomNeeded)) (score: \(String(format: "%.3f", best.score)))", category: "LensPicker")
        lastPickTime = Date()
        lastPickedLens = best.lens

        return (best.lens, best.zoomNeeded)
    }

    // MARK: - Should Re-evaluate

    /// Check if lens selection should be re-evaluated
    /// - Parameters:
    ///   - currentHeight: Current measured subject height
    ///   - targetHeight: Target subject height
    /// - Returns: True if re-evaluation is recommended
    func shouldReevaluate(currentHeight: CGFloat, targetHeight: CGFloat) -> Bool {
        let heightDelta = abs(currentHeight - targetHeight) / max(targetHeight, 0.001)

        // Re-evaluate if height difference is > 5%
        return heightDelta > 0.05
    }

    // MARK: - Reset

    /// Reset debounce timer (useful when switching templates)
    func reset() {
        lastPickTime = nil
        lastPickedLens = nil
    }
}
