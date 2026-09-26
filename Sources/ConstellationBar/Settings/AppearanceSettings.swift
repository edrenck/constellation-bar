import AppKit

/// Builds the appearance section.
extension ConfigurationWindowController {
    func buildAppearanceSettings(in stack: NSStackView) {
        configureAppearanceControls()
        coveCornerRadiusSlider.target = self; coveCornerRadiusSlider.action = #selector(visualChanged)
        coveCornerRadiusSlider.setAccessibilityLabel("Desktop corner radius")
        coveCornerRadiusSlider.toolTip = "Match the corners of this display. Radius stays the same when bar size changes."
        coveCornerRadiusLabel.widthAnchor.constraint(equalToConstant: 50).isActive = true
        nativeColorPopup.addItems(withTitles: BarAppearance.nativeColors.map(\.title))
        nativeColorPopup.target = self
        nativeColorPopup.action = #selector(nativeColorChanged)
        typesetSchemePopup.addItems(withTitles: TypesetScheme.allCases.map(\.title))
        typesetSchemePopup.target = self
        typesetSchemePopup.action = #selector(typesetSchemeChanged)
        typesetVariantPopup.target = self
        typesetVariantPopup.action = #selector(typesetVariantChanged)
        resetAppearanceButton.title = "Reset appearance"
        resetAppearanceButton.target = self
        resetAppearanceButton.action = #selector(resetAppearance)
        let gallery = NSStackView()
        gallery.orientation = .horizontal
        gallery.distribution = .fillEqually
        gallery.spacing = 8
        for family in AppearanceFamily.allCases {
            let choice = family.representative
            let button = AppearanceChoiceButton(choice: choice)
            button.target = self
            button.action = #selector(appearanceChanged(_:))
            gallery.addArrangedSubview(button)
            appearanceButtons.append(button)
        }
        gallery.heightAnchor.constraint(equalToConstant: 100).isActive = true
        appearanceDetail.font = .systemFont(ofSize: 12)
        appearanceDetail.textColor = .secondaryLabelColor
        let section = makeSection(title: "Bar appearance", rows: [
            gallery,
            formRow("Color", nativeColorPopup),
            formRow("Color scheme", typesetSchemePopup),
            formRow("Variation", typesetVariantPopup),
            appearanceDetail,
            formRow("macOS mode", modePopup),
            formRow("Cove Rail", coveBorderButton),
            formRow("Desktop corners", NSStackView(views: [coveCornerRadiusSlider, coveCornerRadiusLabel])),
            formRow("Density", densityPopup),
            resetAppearanceButton
        ])
        gallery.widthAnchor.constraint(equalTo: section.widthAnchor, constant: -32).isActive = true
        stack.addArrangedSubview(section)
    }
    func syncAppearanceControls(_ local: BarConfig) {
        let typeset = local.appearance.family == .typeset
        nativeColorPopup.selectItem(at: BarAppearance.nativeColors.firstIndex(of: local.appearance) ?? 0)
        nativeColorPopup.superview?.isHidden = typeset
        typesetSchemePopup.superview?.isHidden = !typeset
        typesetVariantPopup.superview?.isHidden = !typeset || local.typesetScheme.variants.count == 1
        typesetSchemePopup.selectItem(at: TypesetScheme.allCases.firstIndex(of: local.typesetScheme) ?? 0)
        typesetVariantPopup.removeAllItems()
        typesetVariantPopup.addItems(withTitles: local.typesetScheme.variants.map { local.typesetScheme.variantTitle($0) })
        typesetVariantPopup.selectItem(at: local.typesetScheme.variants.firstIndex(of: local.typesetVariant) ?? 0)
        modePopup.isEnabled = local.appearance.isNative
        modePopup.superview?.isHidden = !local.appearance.isNative
        coveBorderButton.superview?.isHidden = local.appearance != .cove
        coveCornerRadiusSlider.superview?.superview?.isHidden = !local.usesCoveScreenBorder
        for button in appearanceButtons {
            button.state = button.choice.family == local.appearance.family ? .on : .off
            button.previewAppearance = button.choice.family == .native && !typeset ? local.appearance : button.choice
            button.mode = local.themeMode
            button.scheme = local.typesetScheme
            button.variant = local.typesetVariant
            button.needsDisplay = true
        }
        appearanceDetail.stringValue = typeset
            ? "Typeset › \(local.typesetScheme.title)" + (local.typesetScheme.variants.count > 1 ? " › \(local.typesetScheme.variantTitle(local.typesetVariant))" : "") + ". Monospaced type and a bracketed selection."
            : "Native › \(local.appearance.title). " + local.appearance.subtitle
    }

    @objc func nativeColorChanged() {
        guard BarAppearance.nativeColors.indices.contains(nativeColorPopup.indexOfSelectedItem) else { return }
        let color = BarAppearance.nativeColors[nativeColorPopup.indexOfSelectedItem]
        editDisplay({ $0.appearance = color }, shared: { $0.appearance = color })
        commit()
    }
    @objc func typesetSchemeChanged() {
        guard TypesetScheme.allCases.indices.contains(typesetSchemePopup.indexOfSelectedItem) else { return }
        let scheme = TypesetScheme.allCases[typesetSchemePopup.indexOfSelectedItem]
        editDisplay({ $0.typesetScheme = scheme; $0.typesetVariant = scheme.defaultVariant },
                    shared: { $0.typesetScheme = scheme; $0.typesetVariant = scheme.defaultVariant })
        commit()
    }
    @objc func typesetVariantChanged() {
        let scheme = displayConfig.typesetScheme
        guard scheme.variants.indices.contains(typesetVariantPopup.indexOfSelectedItem) else { return }
        let variant = scheme.variants[typesetVariantPopup.indexOfSelectedItem]
        editDisplay({ $0.typesetVariant = variant }, shared: { $0.typesetVariant = variant })
        commit()
    }
}
