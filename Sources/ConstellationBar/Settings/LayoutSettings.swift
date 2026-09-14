import AppKit

/// Builds the layout section.
extension ConfigurationWindowController {
    func buildLayoutSettings(in stack: NSStackView) {
        displayEditor.onChange = { [weak self] id, override in
            guard let self else { return }
            self.config.displayOverrides[id] = override
            self.commit()
            self.displayEditor.sync(config: self.config)
        }
        displayEditor.onCopyToAll = { [weak self] sourceID, override in
            guard let self else { return }
            for screen in NSScreen.screens where screen.configurationID != sourceID {
                self.config.displayOverrides[screen.configurationID] = self.config.resolvedOverride(for: sourceID)
            }
            self.commit()
            self.displayEditor.sync(config: self.config)
        }
        barPresentationPopup.addItems(withTitles: BarPresentation.allCases.map(\.title))
        widgetAlignmentPopup.addItems(withTitles: WidgetAlignment.allCases.map(\.title))
        for popup in [barPresentationPopup, widgetAlignmentPopup] {
            popup.target = self; popup.action = #selector(layoutChanged)
        }
        stack.addArrangedSubview(makeSection(title: "Shared display defaults", rows: [
            formRow("Show bars on", displayPopup), formRow("Bar shape", barPresentationPopup),
            formRow("Alignment", widgetAlignmentPopup), fullscreenButton
        ]))
        stack.addArrangedSubview(makeSection(title: "Per-display setup", rows: [displayEditor]))
    }
}
