import AppKit

/// Builds the layout section.
extension ConfigurationWindowController {
    func buildLayoutSettings(in stack: NSStackView) {
        let displayChanged: (String, DisplayOverride) -> Void = { [weak self] id, override in
            guard let self else { return }
            self.config.displayOverrides[id] = override
            self.commit()
        }
        displayEditor.onChange = displayChanged
        widgetEditor.onChange = displayChanged
        displayEditor.onCopyToAll = { [weak self] sourceID, override in
            guard let self else { return }
            for screen in NSScreen.screens where screen.configurationID != sourceID {
                self.config.displayOverrides[screen.configurationID] = self.config.resolvedOverride(for: sourceID)
            }
            self.commit()
        }
        barPresentationPopup.addItems(withTitles: BarPresentation.allCases.map(\.title))
        compositionPopup.addItems(withTitles: BarLayout.allCases.map(\.title))
        compositionPopup.target = self; compositionPopup.action = #selector(compositionChanged)
        widgetAlignmentPopup.addItems(withTitles: WidgetAlignment.allCases.map(\.title))
        for popup in [barPresentationPopup, widgetAlignmentPopup] {
            popup.target = self; popup.action = #selector(layoutChanged)
        }
        stack.addArrangedSubview(makeSection(title: "Bar layout", rows: [
            formRow("Composition", compositionPopup),
            formRow("Alignment", widgetAlignmentPopup)
        ]))
        stack.addArrangedSubview(makeSection(title: "Display behavior", rows: [displayEditor]))
    }
}
