//
//  Haptics.swift
//  TemplateCam
//
//  Haptic feedback wrapper with cooldown
//

import UIKit

class Haptics {
    static let shared = Haptics()

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()

    private var lastLightHapticTime: Date?
    private let cooldownInterval: TimeInterval = 2.0  // 2 seconds cooldown for light haptics

    private init() {
        // Prepare generators for low latency
        lightImpact.prepare()
        mediumImpact.prepare()
        selection.prepare()
    }

    // MARK: - Light Haptic (with cooldown)

    /// Trigger light haptic with cooldown (for alignment feedback)
    func triggerLight() {
        let now = Date()

        // Check cooldown
        if let lastTime = lastLightHapticTime {
            let elapsed = now.timeIntervalSince(lastTime)
            if elapsed < cooldownInterval {
                return  // Still in cooldown period
            }
        }

        lightImpact.impactOccurred()
        lastLightHapticTime = now
        lightImpact.prepare()  // Re-prepare for next use
    }

    // MARK: - Other Haptics (no cooldown)

    /// Trigger medium impact (e.g., button press)
    func triggerMedium() {
        mediumImpact.impactOccurred()
        mediumImpact.prepare()
    }

    /// Trigger heavy impact (e.g., capture photo)
    func triggerHeavy() {
        heavyImpact.impactOccurred()
        heavyImpact.prepare()
    }

    /// Trigger selection haptic (e.g., slider adjustment)
    func triggerSelection() {
        selection.selectionChanged()
        selection.prepare()
    }

    /// Trigger success notification
    func triggerSuccess() {
        notification.notificationOccurred(.success)
    }

    /// Trigger warning notification
    func triggerWarning() {
        notification.notificationOccurred(.warning)
    }

    /// Trigger error notification
    func triggerError() {
        notification.notificationOccurred(.error)
    }

    // MARK: - Reset

    /// Reset cooldown (useful when switching templates or scenes)
    func resetCooldown() {
        lastLightHapticTime = nil
    }
}
