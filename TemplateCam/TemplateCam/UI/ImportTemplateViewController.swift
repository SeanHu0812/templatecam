//
//  ImportTemplateViewController.swift
//  TemplateCam
//
//  Import a reference photo and generate a template
//

import UIKit
import PhotosUI

protocol ImportTemplateDelegate: AnyObject {
    func didImportTemplate(_ template: Template)
}

class ImportTemplateViewController: UIViewController {

    // MARK: - Properties

    weak var delegate: ImportTemplateDelegate?

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Import Template"
        label.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let instructionLabel: UILabel = {
        let label = UILabel()
        label.text = "Select a photo with a single person to create a new template"
        label.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let selectButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Select Photo", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 12
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private let previewImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .systemGray6
        imageView.layer.cornerRadius = 12
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private var selectedImage: UIImage?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        setupUI()
        setupActions()
    }

    private func setupUI() {
        view.addSubview(titleLabel)
        view.addSubview(instructionLabel)
        view.addSubview(previewImageView)
        view.addSubview(selectButton)
        view.addSubview(activityIndicator)

        let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = cancelButton

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            instructionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            instructionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            instructionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            previewImageView.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 24),
            previewImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            previewImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            previewImageView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.4),

            selectButton.topAnchor.constraint(equalTo: previewImageView.bottomAnchor, constant: 32),
            selectButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            selectButton.widthAnchor.constraint(equalToConstant: 200),
            selectButton.heightAnchor.constraint(equalToConstant: 50),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func setupActions() {
        selectButton.addTarget(self, action: #selector(selectPhotoTapped), for: .touchUpInside)
    }

    // MARK: - Actions

    @objc private func selectPhotoTapped() {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    // MARK: - Generate Template

    private func generateTemplate(from image: UIImage) {
        activityIndicator.startAnimating()
        selectButton.isEnabled = false

        TemplateGenerator.generateTemplate(from: image) { [weak self] result in
            guard let self = self else { return }

            self.activityIndicator.stopAnimating()
            self.selectButton.isEnabled = true

            switch result {
            case .success(let template):
                // Save template
                _ = TemplateStore.shared.save(template)

                // Show success
                let alert = UIAlertController(
                    title: "Template Created",
                    message: "Template '\(template.id)' has been saved successfully",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "Use Template", style: .default) { _ in
                    self.delegate?.didImportTemplate(template)
                    self.dismiss(animated: true)
                })
                alert.addAction(UIAlertAction(title: "Create Another", style: .default) { _ in
                    self.previewImageView.image = nil
                })
                self.present(alert, animated: true)

            case .failure(let error):
                let alert = UIAlertController(
                    title: "Error",
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
            }
        }
    }
}

// MARK: - PHPicker Delegate

extension ImportTemplateViewController: PHPickerViewControllerDelegate {

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        guard let result = results.first else { return }

        result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
            guard let self = self, let image = object as? UIImage else {
                return
            }

            DispatchQueue.main.async {
                self.previewImageView.image = image
                self.selectedImage = image

                // Automatically generate template
                self.generateTemplate(from: image)
            }
        }
    }
}
