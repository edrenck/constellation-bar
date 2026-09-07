import AppKit

/// Builds the layout section.
extension ConfigurationWindowController {
    func buildLayoutSettings(in stack: NSStackView) {
        layoutPopup.addItems(withTitles: BarLayout.allCases.map(\.title))
        placementPopup.addItems(withTitles: WidgetPlacement.allCases.map(\.title))
        for popup in [layoutPopup, placementPopup] { popup.target = self; popup.action = #selector(layoutChanged) }
        stack.addArrangedSubview(makeSection(title: "Composition", rows: [
            formRow("Layout", layoutPopup), formRow("Placement", placementPopup),
            NSTextField(wrappingLabelWithString: "Rail gathers workspaces and status on one surface. Islands separates each group. Compact keeps only workspaces and status icons. Workspaces and widgets stay accessible through overflow menus on small displays.")
        ]))
        orderedWidgets.orientation = .vertical
        orderedWidgets.alignment = .leading
        orderedWidgets.spacing = 6
        stack.addArrangedSubview(makeSection(title: "Module order", rows: [orderedWidgets]))
    }
}
