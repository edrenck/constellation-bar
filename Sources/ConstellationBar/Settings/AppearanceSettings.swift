import AppKit

/// Builds the appearance section.
extension ConfigurationWindowController {
    func buildAppearanceSettings(in stack: NSStackView) {
        configureAppearanceControls()
        resetAppearanceButton.title = "Reset shared appearance"
        resetAppearanceButton.target = self
        resetAppearanceButton.action = #selector(resetAppearance)
        let gallery = NSStackView()
        gallery.orientation = .horizontal
        gallery.distribution = .fillEqually
        gallery.spacing = 8
        for choice in BarAppearance.allCases {
            let button = AppearanceChoiceButton(choice: choice)
            button.target = self
            button.action = #selector(appearanceChanged(_:))
            gallery.addArrangedSubview(button)
            appearanceButtons.append(button)
        }
        gallery.heightAnchor.constraint(equalToConstant: 100).isActive = true
        appearanceDetail.font = .systemFont(ofSize: 12)
        appearanceDetail.textColor = .secondaryLabelColor
        stack.addArrangedSubview(makeSection(title: "Default appearance", rows: [
            gallery, appearanceDetail,
            formRow("Native mode", modePopup),
            formRow("Cove Rail", coveBorderButton),
            formRow("Density", densityPopup),
            resetAppearanceButton
        ]))

    }
}
