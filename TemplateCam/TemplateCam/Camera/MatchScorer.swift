//
//  MatchScorer.swift
//  TemplateCam
//
//  Score live camera framing and pose against template
//

import Foundation
import Vision
import CoreGraphics

// MARK: - Coaching Instruction

enum CoachingInstruction: String {
    case stepForward = "Step Forward"
    case stepBack = "Step Back"
    case rotateClockwise = "Rotate Right"
    case rotateCounterclockwise = "Rotate Left"
    case hold = "Hold Still"
    case perfect = "Perfect!"

    var icon: String {
        switch self {
        case .stepForward: return "arrow.forward"
        case .stepBack: return "arrow.backward"
        case .rotateClockwise: return "arrow.clockwise"
        case .rotateCounterclockwise: return "arrow.counterclockwise"
        case .hold: return "hand.raised.fill"
        case .perfect: return "checkmark.circle.fill"
        }
    }
}

// MARK: - Match Result

struct MatchResult {
    let framingScore: CGFloat       // 0-1, based on subject height match
    let poseScore: CGFloat          // 0-1, based on pose similarity
    let overallScore: CGFloat       // Weighted average
    let primaryInstruction: CoachingInstruction
}

// MARK: - Match Scorer

class MatchScorer {

    // MARK: - Score Match

    /// Score how well the live camera matches the template
    /// - Parameters:
    ///   - liveSubjectHeight: Current subject height (normalized 0-1)
    ///   - targetHeight: Target subject height from template
    ///   - livePose: Live pose observation (optional)
    ///   - templateKeybones: Template keybones
    /// - Returns: Match result with scores and coaching instruction
    static func scoreMatch(
        liveSubjectHeight: CGFloat,
        targetHeight: CGFloat,
        livePose: VNHumanBodyPoseObservation?,
        templateKeybones: [[String]]
    ) -> MatchResult {

        // 1. Framing score (subject height match)
        let framingScore = calculateFramingScore(
            liveHeight: liveSubjectHeight,
            targetHeight: targetHeight
        )

        // 2. Pose score (keybone angles)
        let poseScore = calculatePoseScore(
            livePose: livePose,
            templateKeybones: templateKeybones
        )

        // 3. Overall score (weighted: 60% framing, 40% pose)
        let overallScore = framingScore * 0.6 + poseScore * 0.4

        // 4. Determine coaching instruction
        let instruction = determineInstruction(
            framingScore: framingScore,
            liveHeight: liveSubjectHeight,
            targetHeight: targetHeight,
            overallScore: overallScore
        )

        return MatchResult(
            framingScore: framingScore,
            poseScore: poseScore,
            overallScore: overallScore,
            primaryInstruction: instruction
        )
    }

    // MARK: - Framing Score

    private static func calculateFramingScore(liveHeight: CGFloat, targetHeight: CGFloat) -> CGFloat {
        let heightDiff = abs(liveHeight - targetHeight)
        let tolerance: CGFloat = 0.08  // 8% tolerance

        // Score decreases linearly as difference increases
        let score = max(0, 1.0 - (heightDiff / tolerance))
        return score
    }

    // MARK: - Pose Score

    private static func calculatePoseScore(
        livePose: VNHumanBodyPoseObservation?,
        templateKeybones: [[String]]
    ) -> CGFloat {
        guard let pose = livePose else {
            return 0.5  // Neutral score if no pose detected
        }

        var angleScores: [CGFloat] = []

        // Compare angles of key bones
        for bone in templateKeybones {
            guard bone.count == 2 else { continue }

            guard let startJoint = VNHumanBodyPoseObservation.JointName(rawValue: VNRecognizedPointKey(rawValue: bone[0])),
                  let endJoint = VNHumanBodyPoseObservation.JointName(rawValue: VNRecognizedPointKey(rawValue: bone[1])) else {
                continue
            }

            guard let startPoint = try? pose.recognizedPoint(startJoint),
                  let endPoint = try? pose.recognizedPoint(endJoint),
                  startPoint.confidence > 0.5,
                  endPoint.confidence > 0.5 else {
                continue
            }

            // Calculate angle of bone
            let dx = endPoint.location.x - startPoint.location.x
            let dy = endPoint.location.y - startPoint.location.y
            let angle = atan2(dy, dx)

            // For simplicity, we check if the bone is roughly in expected orientation
            // (This is simplified; in production, you'd compare against template angles)
            // Here we just check if joints are detected with good confidence
            angleScores.append(1.0)
        }

        if angleScores.isEmpty {
            return 0.5
        }

        return angleScores.reduce(0, +) / CGFloat(angleScores.count)
    }

    // MARK: - Determine Instruction

    private static func determineInstruction(
        framingScore: CGFloat,
        liveHeight: CGFloat,
        targetHeight: CGFloat,
        overallScore: CGFloat
    ) -> CoachingInstruction {

        // If overall score is excellent, say perfect
        if overallScore >= 0.85 {
            return .perfect
        }

        // If overall score is good, say hold
        if overallScore >= 0.75 {
            return .hold
        }

        // Otherwise, give height-based instruction
        let heightDiff = liveHeight - targetHeight

        if heightDiff < -0.1 {
            // Subject too small, step forward
            return .stepForward
        } else if heightDiff > 0.1 {
            // Subject too large, step back
            return .stepBack
        } else {
            // Height is okay, but overall score not great (likely pose issue)
            return .hold
        }
    }
}
