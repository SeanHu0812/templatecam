//
//  TemplateControlsView.swift
//  TemplateCam
//
//  Manual controls for template tone and white balance adjustments
//

import UIKit

protocol TemplateControlsDelegate: AnyObject {
    func controlsDidUpdate(tone: Template.CameraTargets.Tone, wb: Template.CameraTargets.WhiteBalance)
}

class TemplateControlsView: UIView {

    // MARK: - Properties

    weak var delegate: TemplateControlsDelegate?

    private var tone: Template.CameraTargets.Tone
    private var whiteBalance: Template.CameraTargets.WhiteBalance

    private let scrollView = UIScrollView()
    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private var isExpanded = false

    // MARK: - Initialization

    init(tone: Template.CameraTargets.Tone, whiteBalance: Template.CameraTargets.WhiteBalance) {
        self.tone = tone
        self.whiteBalance = whiteBalance
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) {
        self.tone = Template.CameraTargets.Tone(
            exposureEV: 0, contrast: 1, highlights: 0,
            shadows: 0, saturation: 1, vibrance: 0, sharpness: 0
        )
        self.whiteBalance = Template.CameraTargets.WhiteBalance(temperature: 5500, tint: 0)
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        backgroundColor = UIColor.black.withAlphaComponent(0.85)
        layer.cornerRadius = 16
        clipsToBounds = true

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -16),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32)
        ])

        setupControls()
    }

    private func setupControls() {
        // Exposure EV
        addSlider(
            title: "Exposure",
            value: Float(tone.exposureEV),
            range: -1.0...1.0,
            tag: 0
        )

        // Contrast
        addSlider(
            title: "Contrast",
            value: Float(tone.contrast),
            range: 0.8...1.3,
            tag: 1
        )

        // Highlights
        addSlider(
            title: "Highlights",
            value: Float(tone.highlights),
            range: -0.3...0.3,
            tag: 2
        )

        // Shadows
        addSlider(
            title: "Shadows",
            value: Float(tone.shadows),
            range: -0.3...0.3,
            tag: 3
        )

        // Saturation
        addSlider(
            title: "Saturation",
            value: Float(tone.saturation),
            range: 0.8...1.3,
            tag: 4
        )

        // Vibrance
        addSlider(
            title: "Vibrance",
            value: Float(tone.vibrance),
            range: 0.0...0.5,
            tag: 5
        )

        // Sharpness
        addSlider(
            title: "Sharpness",
            value: Float(tone.sharpness),
            range: 0.0...0.3,
            tag: 6
        )

        // WB Temperature
        addSlider(
            title: "WB Temperature",
            value: Float(whiteBalance.temperature),
            range: 3000...7500,
            tag: 7
        )

        // WB Tint
        addSlider(
            title: "WB Tint",
            value: Float(whiteBalance.tint),
            range: -20...20,
            tag: 8
        )
    }

    private func addSlider(title: String, value: Float, range: ClosedRange<Float>, tag: Int) {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = title
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false

        let valueLabel = UILabel()
        valueLabel.text = formatValue(value, tag: tag)
        valueLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        valueLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        valueLabel.textAlignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.tag = tag + 1000  // Offset to avoid conflicts

        let slider = UISlider()
        slider.minimumValue = range.lowerBound
        slider.maximumValue = range.upperBound
        slider.value = value
        slider.tag = tag
        slider.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderTouchUp(_:)), for: .touchUpInside)
        slider.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(label)
        container.addSubview(valueLabel)
        container.addSubview(slider)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),

            valueLabel.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            valueLabel.widthAnchor.constraint(equalToConstant: 80),

            slider.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),
            slider.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            slider.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        stackView.addArrangedSubview(container)
    }

    @objc private func sliderChanged(_ slider: UISlider) {
        // Update value label
        if let valueLabel = viewWithTag(slider.tag + 1000) as? UILabel {
            valueLabel.text = formatValue(slider.value, tag: slider.tag)
        }

        // Update tone/WB values
        updateValues(from: slider)
    }

    @objc private func sliderTouchUp(_ slider: UISlider) {
        // Notify delegate
        delegate?.controlsDidUpdate(tone: tone, wb: whiteBalance)

        // Haptic feedback
        Haptics.shared.triggerSelection()
    }

    private func updateValues(from slider: UISlider) {
        let value = CGFloat(slider.value)

        switch slider.tag {
        case 0: tone.exposureEV = value
        case 1: tone.contrast = value
        case 2: tone.highlights = value
        case 3: tone.shadows = value
        case 4: tone.saturation = value
        case 5: tone.vibrance = value
        case 6: tone.sharpness = value
        case 7: whiteBalance.temperature = value
        case 8: whiteBalance.tint = value
        default: break
        }
    }

    private func formatValue(_ value: Float, tag: Int) -> String {
        switch tag {
        case 7: // Temperature
            return "\(Int(value))K"
        case 8: // Tint
            return String(format: "%+.0f", value)
        case 0, 2, 3: // EV, Highlights, Shadows
            return String(format: "%+.2f", value)
        case 1, 4: // Contrast, Saturation
            return String(format: "%.2f", value)
        case 5, 6: // Vibrance, Sharpness
            return String(format: "%.2f", value)
        default:
            return String(format: "%.2f", value)
        }
    }

    // MARK: - Public Methods

    func updateTemplate(tone: Template.CameraTargets.Tone, whiteBalance: Template.CameraTargets.WhiteBalance) {
        self.tone = tone
        self.whiteBalance = whiteBalance

        // Update sliders
        for case let slider as UISlider in stackView.arrangedSubviews.compactMap({ $0.subviews.compactMap { $0 as? UISlider } }).flatMap({ $0 }) {
            switch slider.tag {
            case 0: slider.value = Float(tone.exposureEV)
            case 1: slider.value = Float(tone.contrast)
            case 2: slider.value = Float(tone.highlights)
            case 3: slider.value = Float(tone.shadows)
            case 4: slider.value = Float(tone.saturation)
            case 5: slider.value = Float(tone.vibrance)
            case 6: slider.value = Float(tone.sharpness)
            case 7: slider.value = Float(whiteBalance.temperature)
            case 8: slider.value = Float(whiteBalance.tint)
            default: break
            }

            // Update value label
            if let valueLabel = viewWithTag(slider.tag + 1000) as? UILabel {
                valueLabel.text = formatValue(slider.value, tag: slider.tag)
            }
        }
    }

    func getCurrentTone() -> Template.CameraTargets.Tone {
        return tone
    }

    func getCurrentWhiteBalance() -> Template.CameraTargets.WhiteBalance {
        return whiteBalance
    }
}
