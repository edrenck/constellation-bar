import AppKit

extension ConfigurationWindowController {
    func makeSection(title: String, rows: [NSView]) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.62).cgColor
        container.layer?.cornerRadius = 12
        container.layer?.cornerCurve = .continuous
        container.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        container.addSubview(stack)
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(heading)
        rows.forEach { stack.addArrangedSubview($0) }
        NSLayoutConstraint.activateOwned([
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 560),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
        ], owner: "settings.section.\(title)")
        sections[buildingSection, default: []].append(container)
        return container
    }

    func formRow(_ title: String, _ control: NSView) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        let label = NSTextField(labelWithString: title)
        label.textColor = .secondaryLabelColor
        label.widthAnchor.constraint(equalToConstant: 120).isActive = true
        row.addArrangedSubview(label)
        row.addArrangedSubview(control)
        control.widthAnchor.constraint(greaterThanOrEqualToConstant: control is NSButton ? 160 : 230).isActive = true
        return row
    }

    func coordinateRow() -> NSView {
        let fields = NSStackView()
        fields.orientation = .horizontal
        fields.spacing = 8
        latitudeField.placeholderString = "Latitude"
        longitudeField.placeholderString = "Longitude"
        latitudeField.widthAnchor.constraint(equalToConstant: 108).identified("settings.latitude.width").isActive = true
        longitudeField.widthAnchor.constraint(equalToConstant: 108).identified("settings.longitude.width").isActive = true
        fields.addArrangedSubview(latitudeField)
        fields.addArrangedSubview(longitudeField)
        return formRow("Coordinates", fields)
    }

}
