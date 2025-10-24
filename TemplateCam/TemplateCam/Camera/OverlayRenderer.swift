//
//  OverlayRenderer.swift
//  TemplateCam
//
//  Draw template overlays (keybones, target box, horizon) on preview
//

import UIKit
import Vision

class OverlayRenderer {

    // MARK: - Properties

    private var skeletonLayer: CAShapeLayer?
    private var targetBoxLayer: CAShapeLayer?
    private var horizonLayer: CAShapeLayer?

    private let overlayColor = UIColor.white.withAlphaComponent(0.7)
    private let lineWidth: CGFloat = 2.0

    // MARK: - Setup Layers

    /// Setup overlay layers on the preview view
    /// - Parameter previewView: View to add layers to
    func setupLayers(on previewView: UIView) {
        // Remove existing layers
        removeLayers()

        // Skeleton layer
        skeletonLayer = CAShapeLayer()
        skeletonLayer?.strokeColor = overlayColor.cgColor
        skeletonLayer?.fillColor = UIColor.clear.cgColor
        skeletonLayer?.lineWidth = lineWidth
        skeletonLayer?.lineCap = .round
        skeletonLayer?.lineJoin = .round
        previewView.layer.addSublayer(skeletonLayer!)

        // Target box layer
        targetBoxLayer = CAShapeLayer()
        targetBoxLayer?.strokeColor = UIColor.green.withAlphaComponent(0.6).cgColor
        targetBoxLayer?.fillColor = UIColor.clear.cgColor
        targetBoxLayer?.lineWidth = lineWidth
        targetBoxLayer?.lineDashPattern = [8, 4]
        previewView.layer.addSublayer(targetBoxLayer!)

        // Horizon layer
        horizonLayer = CAShapeLayer()
        horizonLayer?.strokeColor = UIColor.cyan.withAlphaComponent(0.5).cgColor
        horizonLayer?.fillColor = UIColor.clear.cgColor
        horizonLayer?.lineWidth = 1.5
        horizonLayer?.lineDashPattern = [12, 6]
        previewView.layer.addSublayer(horizonLayer!)
    }

    /// Remove all overlay layers
    func removeLayers() {
        skeletonLayer?.removeFromSuperlayer()
        targetBoxLayer?.removeFromSuperlayer()
        horizonLayer?.removeFromSuperlayer()
        skeletonLayer = nil
        targetBoxLayer = nil
        horizonLayer = nil
    }

    // MARK: - Update Overlays

    /// Update overlays with template and live pose
    /// - Parameters:
    ///   - template: Template with keybones and target box
    ///   - poseObservation: Live Vision pose observation (optional)
    ///   - viewBounds: Bounds of the preview view
    ///   - previewLayer: AVCaptureVideoPreviewLayer for coordinate conversion
    func updateOverlays(
        template: Template,
        poseObservation: VNHumanBodyPoseObservation?,
        viewBounds: CGRect,
        previewLayer: AVCaptureVideoPreviewLayer
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // 1. Draw skeleton from live pose
        if let pose = poseObservation {
            drawSkeleton(keybones: template.subject.keybones, pose: pose, viewBounds: viewBounds, previewLayer: previewLayer)
        } else {
            skeletonLayer?.path = nil
        }

        // 2. Draw target box
        drawTargetBox(bbox: template.subject.bbox, viewBounds: viewBounds)

        // 3. Draw horizon
        if let horizonY = template.background.horizonY {
            drawHorizon(horizonY: horizonY, viewBounds: viewBounds)
        } else {
            horizonLayer?.path = nil
        }

        CATransaction.commit()
    }

    // MARK: - Draw Skeleton

    private func drawSkeleton(
        keybones: [[String]],
        pose: VNHumanBodyPoseObservation,
        viewBounds: CGRect,
        previewLayer: AVCaptureVideoPreviewLayer
    ) {
        let path = UIBezierPath()

        for bone in keybones {
            guard bone.count == 2 else { continue }

            // Get joint names
            guard let startJoint = VNHumanBodyPoseObservation.JointName(rawValue: VNRecognizedPointKey(rawValue: bone[0])),
                  let endJoint = VNHumanBodyPoseObservation.JointName(rawValue: VNRecognizedPointKey(rawValue: bone[1])) else {
                continue
            }

            // Get recognized points
            guard let startPoint = try? pose.recognizedPoint(startJoint),
                  let endPoint = try? pose.recognizedPoint(endJoint),
                  startPoint.confidence > 0.3,
                  endPoint.confidence > 0.3 else {
                continue
            }

            // Convert from Vision coordinates (normalized, bottom-left origin) to view coordinates
            let startViewPoint = convertVisionPoint(startPoint.location, viewBounds: viewBounds, previewLayer: previewLayer)
            let endViewPoint = convertVisionPoint(endPoint.location, viewBounds: viewBounds, previewLayer: previewLayer)

            // Draw line
            path.move(to: startViewPoint)
            path.addLine(to: endViewPoint)
        }

        skeletonLayer?.path = path.cgPath
    }

    // MARK: - Draw Target Box

    private func drawTargetBox(bbox: Template.Subject.BBox, viewBounds: CGRect) {
        // Convert normalized bbox (0-1) to view coordinates
        let x = bbox.x * viewBounds.width
        let y = bbox.y * viewBounds.height
        let w = bbox.w * viewBounds.width
        let h = bbox.h * viewBounds.height

        let rect = CGRect(x: x, y: y, width: w, height: h)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 8)

        targetBoxLayer?.path = path.cgPath
    }

    // MARK: - Draw Horizon

    private func drawHorizon(horizonY: CGFloat, viewBounds: CGRect) {
        let y = horizonY * viewBounds.height

        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: viewBounds.width, y: y))

        horizonLayer?.path = path.cgPath
    }

    // MARK: - Fade Animations

    /// Fade out overlays
    func fadeOut(duration: TimeInterval = 0.3) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)

        skeletonLayer?.opacity = 0
        targetBoxLayer?.opacity = 0
        horizonLayer?.opacity = 0

        CATransaction.commit()
    }

    /// Fade in overlays
    func fadeIn(duration: TimeInterval = 0.3) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)

        skeletonLayer?.opacity = 1
        targetBoxLayer?.opacity = 1
        horizonLayer?.opacity = 1

        CATransaction.commit()
    }

    // MARK: - Coordinate Conversion

    /// Convert Vision normalized point (bottom-left origin) to view coordinates
    private func convertVisionPoint(
        _ point: CGPoint,
        viewBounds: CGRect,
        previewLayer: AVCaptureVideoPreviewLayer
    ) -> CGPoint {
        // Vision uses normalized coordinates with bottom-left origin
        // We need to convert to view coordinates (top-left origin)

        // First, convert to layer coordinates
        let layerPoint = previewLayer.layerPointConverted(fromCaptureDevicePoint: point)

        // Flip Y-axis for Vision's bottom-left origin
        let flippedY = viewBounds.height - layerPoint.y

        return CGPoint(x: layerPoint.x, y: flippedY)
    }

    /// Hide all overlays
    func hide() {
        skeletonLayer?.isHidden = true
        targetBoxLayer?.isHidden = true
        horizonLayer?.isHidden = true
    }

    /// Show all overlays
    func show() {
        skeletonLayer?.isHidden = false
        targetBoxLayer?.isHidden = false
        horizonLayer?.isHidden = false
    }
}
