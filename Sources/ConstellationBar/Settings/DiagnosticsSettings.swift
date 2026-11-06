import AppKit

final class DiagnosticRow: NSStackView {
    let status = NSTextField(labelWithString: "Waiting")
    let detail = NSTextField(wrappingLabelWithString: "")
    init(title: String, actionTitle: String, target: AnyObject, action: Selector, tag: Int) {
        super.init(frame: .zero)
        orientation = .vertical; alignment = .leading; spacing = 5
        let heading = NSStackView(); heading.spacing = 12
        let name = NSTextField(labelWithString: title); name.font = .systemFont(ofSize: 13, weight: .semibold)
        status.font = .systemFont(ofSize: 11, weight: .medium)
        heading.addArrangedSubview(name); heading.addArrangedSubview(status)
        let button = NSButton(title: actionTitle, target: target, action: action); button.tag = tag
        heading.addArrangedSubview(button)
        addArrangedSubview(heading); addArrangedSubview(detail)
        detail.font = .systemFont(ofSize: 12); detail.textColor = .secondaryLabelColor
        detail.isSelectable = true
        detail.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func apply(_ entry: DiagnosticEntry) {
        status.stringValue = entry.health.rawValue
        status.textColor = entry.health == .attention ? .systemOrange : entry.health == .ready ? .systemGreen : .secondaryLabelColor
        detail.stringValue = entry.detail
    }
}

extension ConfigurationWindowController {
    func buildLiveDiagnostics(in stack: NSStackView) {
        let refresh = NSButton(title: "Refresh status", target: self, action: #selector(refreshDiagnostics))
        let copy = NSButton(title: "Copy diagnostic report", target: self, action: #selector(copyDiagnostics))
        diagnosticsFreshness.textColor = .secondaryLabelColor
        stack.addArrangedSubview(makeSection(title: "Live health", rows: [diagnosticsFreshness, NSStackView(views: [refresh, copy])]))
        let workspace = DiagnosticRow(title: "Workspaces", actionTitle: "Settings…", target: self, action: #selector(diagnosticSettings(_:)), tag: -1)
        workspaceDiagnosticRow = workspace
        let fullscreen = DiagnosticRow(title: "Fullscreen visibility", actionTitle: "Settings…", target: self, action: #selector(diagnosticSettings(_:)), tag: -2)
        fullscreenDiagnosticRow = fullscreen
        var rows: [NSView] = [workspace, fullscreen]
        for (index, kind) in IntegrationDiagnostics.widgetKinds.enumerated() {
            let title = configurableItems.contains(.widget(kind)) ? "Settings…" : "Arrange…"
            let row = DiagnosticRow(title: kind.menuTitle, actionTitle: title, target: self, action: #selector(diagnosticSettings(_:)), tag: index)
            diagnosticRows[kind] = row; rows.append(row)
        }
        stack.addArrangedSubview(makeSection(title: "Integrations", rows: rows))
        configPathStatus.isSelectable = true
        configPathStatus.lineBreakMode = .byTruncatingMiddle
        configErrorStatus.textColor = .systemOrange
        configErrorStatus.isSelectable = true
        let reveal = NSButton(title: "Show configuration in Finder", target: self, action: #selector(revealDiagnosticConfig))
        stack.addArrangedSubview(makeSection(title: "Configuration", rows: [configPathStatus, configErrorStatus, reveal]))
    }

    func diagnosticEntries() -> [DiagnosticEntry] {
        // Settings may already reflect a change that the sampler has not completed yet.
        let scope = DisplayScope(config: config, connectedDisplayIDs: NSScreen.screens.map(\.configurationID))
        let matches = diagnostics.sampledPreferences == config.providerPreferences
            && diagnostics.sampledWeather == config.weather && diagnostics.sampledDisplayScope == scope
        return IntegrationDiagnostics.entries(config: config, state: matches ? diagnostics.system : nil, sampledWidgets: diagnostics.sampledWidgets, displayScope: scope)
    }

    func fullscreenDiagnosticEntry() -> DiagnosticEntry {
        let scope = DisplayScope(config: config, connectedDisplayIDs: NSScreen.screens.map(\.configurationID))
        let requested = NSScreen.screens.filter { scope.displayIDs.contains($0.configurationID) && config.forDisplay($0.configurationID).hideInFullscreen }.map(\.displayID)
        return diagnostics.fullscreenEntry(requestedDisplays: Set(requested))
    }

    @objc func refreshDiagnostics() {
        diagnostics.requestRefresh()
        updateDiagnostics()
    }
    @objc func diagnosticSettings(_ sender: NSButton) {
        if sender.tag == -1 { selectWidgetOptions(.workspaces); return }
        if sender.tag == -2 { selectSection(0); return }
        let kinds = IntegrationDiagnostics.widgetKinds
        guard kinds.indices.contains(sender.tag) else { return }
        let kind = kinds[sender.tag]
        if configurableItems.contains(.widget(kind)) { selectWidgetOptions(.widget(kind)) }
        else { selectSection(1) }
    }
    @objc func revealDiagnosticConfig() {
        let url = ConfigFile.writableURL()
        if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        else { NSWorkspace.shared.open(url.deletingLastPathComponent()) }
    }
    func diagnosticReport() -> String {
        let entries = diagnosticEntries()
        let fullscreen = fullscreenDiagnosticEntry()
        return (["ConstellationBar diagnostics", "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)", diagnosticsFreshness.stringValue,
                       "Workspaces: \(diagnostics.workspace)", "\(fullscreen.title) [\(fullscreen.health.rawValue)]: \(fullscreen.detail)"] + (diagnostics.workspaceActionError.map { ["Workspace action: \($0)"] } ?? []) + entries.map { "\($0.title) [\($0.health.rawValue)]: \($0.detail)" }
                      + ["Configuration: \(ConfigFile.writableURL().path)", ConfigurationStore.diagnosticError ?? "No configuration errors reported."]).joined(separator: "\n")
    }
    @objc func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnosticReport(), forType: .string)
    }
}
