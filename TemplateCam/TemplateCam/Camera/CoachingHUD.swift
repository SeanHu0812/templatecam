//
//  CoachingHUD.swift
//  TemplateCam
//
//  Display coaching instructions to user
//

import UIKit

class CoachingHUD: UIView {

    // MARK: - UI Components

    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .white
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let instructionLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let scoreLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        label.textColor = UIColor.white.withAlphaComponent(0.7)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Properties

    private var lastHapticTime: Date?
    private let hapticCooldown: TimeInterval = 2.0

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        addSubview(containerView)
        containerView.addSubview(iconImageView)
        containerView.addSubview(instructionLabel)
        containerView.addSubview(scoreLabel)

        NSLayoutConstraint.activate([
            // Container
            containerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: centerYAnchor),
            containerView.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            containerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 80),

            // Icon
            iconImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            iconImageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 32),
            iconImageView.heightAnchor.constraint(equalToConstant: 32),

            // Instruction
            instructionLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 8),
            instructionLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            instructionLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),

            // Score
            scoreLabel.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 4),
            scoreLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            scoreLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            scoreLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12)
        ])

        // Initially hidden
        alpha = 0
    }

    // MARK: - Update

    /// Update coaching HUD with match result
    /// - Parameter result: Match result with scores and instruction
    func update(with result: MatchResult) {
        instructionLabel.text = result.primaryInstruction.rawValue
        scoreLabel.text = String(format: "Score: %.0f%%", result.overallScore * 100)

        // Set icon
        let iconName = result.primaryInstruction.icon
        iconImageView.image = UIImage(systemName: iconName)

        // Change color based on score
        let color: UIColor
        if result.overallScore >= 0.85 {
            color = .systemGreen
        } else if result.overallScore >= 0.6 {
            color = .systemYellow
        } else {
            color = .systemRed
        }

        iconImageView.tintColor = color
        instructionLabel.textColor = color

        // Show HUD if hidden
        if alpha < 1 {
            UIView.animate(withDuration: 0.3) {
                self.alpha = 1
            }
        }

        // Trigger haptic if score is good
        if result.overallScore >= 0.85 {
            triggerHapticIfNeeded()
        }

        // Log coaching
        Logger.logCoaching(result.primaryInstruction.rawValue, score: result.overallScore)
    }

    /// Hide coaching HUD
    func hide(animated: Bool = true) {
        if animated {
            UIView.animate(withDuration: 0.3) {
                self.alpha = 0
            }
        } else {
            alpha = 0
        }
    }

    /// Show coaching HUD
    func show(animated: Bool = true) {
        if animated {
            UIView.animate(withDuration: 0.3) {
                self.alpha = 1
            }
        } else {
            alpha = 1
        }
    }

    // MARK: - Haptic Feedback

    private func triggerHapticIfNeeded() {
        let now = Date()

        // Check cooldown
        if let lastTime = lastHapticTime {
            let elapsed = now.timeIntervalSince(lastTime)
            if elapsed < hapticCooldown {
                return
            }
        }

        Haptics.shared.triggerLight()
        lastHapticTime = now
    }

    /// Reset haptic cooldown
    func resetHaptic() {
        lastHapticTime = nil
    }
}
