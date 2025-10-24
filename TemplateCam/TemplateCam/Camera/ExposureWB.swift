//
//  ExposureWB.swift
//  TemplateCam
//
//  Apply exposure and white balance settings from template
//

import AVFoundation
import CoreGraphics

class ExposureWB {

    // MARK: - Apply Template Settings

    /// Apply template camera settings to capture device
    /// - Parameters:
    ///   - template: Template with camera targets
    ///   - device: AVCaptureDevice to configure
    static func apply(template: Template, to device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()

            // Apply exposure bias
            if device.isExposureModeSupported(.continuousAutoExposure) {
                let bias = Float(template.cameraTargets.exposureBiasEV)
                let clampedBias = max(device.minExposureTargetBias, min(bias, device.maxExposureTargetBias))
                device.exposureMode = .continuousAutoExposure
                device.setExposureTargetBias(clampedBias)
            }

            // Apply white balance
            if device.isWhiteBalanceModeSupported(.locked) {
                let temperature = Float(template.cameraTargets.wb.temperature)
                let tint = Float(template.cameraTargets.wb.tint)

                let tempTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                    temperature: temperature,
                    tint: tint
                )

                var gains = device.deviceWhiteBalanceGains(for: tempTint)

                // Clamp gains to device limits
                let maxGain = device.maxWhiteBalanceGain
                gains.redGain = max(1.0, min(gains.redGain, maxGain))
                gains.greenGain = max(1.0, min(gains.greenGain, maxGain))
                gains.blueGain = max(1.0, min(gains.blueGain, maxGain))

                device.setWhiteBalanceModeLocked(with: gains)
            }

            device.unlockForConfiguration()

            Logger.logExposureLock(
                ev: Float(template.cameraTargets.exposureBiasEV),
                temperature: template.cameraTargets.wb.temperature,
                tint: template.cameraTargets.wb.tint
            )

        } catch {
            Logger.logError(error, context: "Failed to apply exposure/WB settings")
        }
    }

    // MARK: - Apply Individual Settings

    /// Set exposure bias
    static func setExposureBias(_ bias: CGFloat, to device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()

            if device.isExposureModeSupported(.continuousAutoExposure) {
                let clampedBias = Float(max(CGFloat(device.minExposureTargetBias), min(bias, CGFloat(device.maxExposureTargetBias))))
                device.exposureMode = .continuousAutoExposure
                device.setExposureTargetBias(clampedBias)
            }

            device.unlockForConfiguration()
        } catch {
            Logger.logError(error, context: "Failed to set exposure bias")
        }
    }

    /// Lock white balance with temperature and tint
    static func lockWhiteBalance(temperature: CGFloat, tint: CGFloat, device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()

            if device.isWhiteBalanceModeSupported(.locked) {
                let tempTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                    temperature: Float(temperature),
                    tint: Float(tint)
                )

                var gains = device.deviceWhiteBalanceGains(for: tempTint)

                // Clamp gains
                let maxGain = device.maxWhiteBalanceGain
                gains.redGain = max(1.0, min(gains.redGain, maxGain))
                gains.greenGain = max(1.0, min(gains.greenGain, maxGain))
                gains.blueGain = max(1.0, min(gains.blueGain, maxGain))

                device.setWhiteBalanceModeLocked(with: gains)
            }

            device.unlockForConfiguration()
        } catch {
            Logger.logError(error, context: "Failed to lock white balance")
        }
    }

    /// Unlock white balance and return to continuous auto
    static func unlockWhiteBalance(device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()

            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }

            device.unlockForConfiguration()
        } catch {
            Logger.logError(error, context: "Failed to unlock white balance")
        }
    }

    /// Unlock exposure and return to continuous auto
    static func unlockExposure(device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()

            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }

            device.unlockForConfiguration()
        } catch {
            Logger.logError(error, context: "Failed to unlock exposure")
        }
    }
}
