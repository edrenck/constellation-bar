import AppKit
import ServiceManagement
import UniformTypeIdentifiers

final class FlippedSettingsView: NSView {
    override var isFlipped: Bool { true }
}

final class ConfigurationWindowController: NSWindowController, NSTextFieldDelegate {
    var config: BarConfig
    let onChange: (BarConfig) -> Void
    lazy var preview = ConfigurationPreviewView(config: config)
    var undoStack: [BarConfig] = []
    var lastCommittedConfig: BarConfig
    let undoButton = NSButton(title: "Undo", target: nil, action: nil)
    let resetAppearanceButton = NSButton(title: "Reset Appearance", target: nil, action: nil)

    let sectionsControl = NSSegmentedControl(labels: ["Layout", "Widgets", "Appearance", "Connections", "Application"], trackingMode: .selectOne, target: nil, action: nil)
    var sections: [Int: [NSView]] = [:]
    let layoutPopup = NSPopUpButton()
    let placementPopup = NSPopUpButton()
    let integrationPopup = NSPopUpButton()
    let aerospacePathField = NSTextField()
    let workspaceOrderField = NSTextField()
    let fullscreenButton = NSButton(checkboxWithTitle: "Hide on the display containing a fullscreen window", target: nil, action: nil)
    let localSpacesButton = NSButton(checkboxWithTitle: "Show each display’s own workspaces", target: nil, action: nil)
    let orderedWidgets = NSStackView()
    let modulePopup = NSPopUpButton()
    var providerButtons: [String: NSButton] = [:]
    var moduleRows: [(Set<WidgetKind>, NSView)] = []
    let noModuleOptions = NSTextField(labelWithString: "This module uses your system settings.")
    var displayControls: [(String, NSButton, NSPopUpButton)] = []
    var appearanceButtons: [AppearanceChoiceButton] = []
    let appearanceDetail = NSTextField(wrappingLabelWithString: "")
    let modePopup = NSPopUpButton()
    let coveBorderButton = NSButton(checkboxWithTitle: "Full-width screen border", target: nil, action: nil)
    let densityPopup = NSPopUpButton()
    let workspaceAppsButton = NSButton(checkboxWithTitle: "Show open application icons", target: nil, action: nil)
    var widgetButtons: [WidgetKind: NSButton] = [:]
    let datePopup = NSPopUpButton()
    let artistButton = NSButton(checkboxWithTitle: "Include artist", target: nil, action: nil)
    let hideIdlePlayerButton = NSButton(checkboxWithTitle: "Hide when nothing is playing", target: nil, action: nil)
    let weatherLocationButton = NSButton(checkboxWithTitle: "Show location in bar", target: nil, action: nil)
    let weatherLocationField = NSTextField()
    let latitudeField = NSTextField()
    let longitudeField = NSTextField()
    let weatherUnitPopup = NSPopUpButton()
    let displayPopup = NSPopUpButton()
    let refreshPopup = NSPopUpButton()
    let launchAtLoginButton = NSButton(checkboxWithTitle: "Launch ConstellationBar at login", target: nil, action: nil)
    let aerospaceStatus = NSTextField(labelWithString: "")
    let tailscaleStatus = NSTextField(labelWithString: "")
    let mediaStatus = NSTextField(labelWithString: "")
    let weatherStatus = NSTextField(labelWithString: "")
    let configPathStatus = NSTextField(labelWithString: "")

    init(config: BarConfig, onChange: @escaping (BarConfig) -> Void) {
        self.config = config
        self.lastCommittedConfig = config
        self.onChange = onChange
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Customize ConstellationBar"
        window.minSize = NSSize(width: 700, height: 600)
        window.collectionBehavior = [.moveToActiveSpace]
        super.init(window: window)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActive), name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateDiagnostics), name: IntegrationDiagnostics.changed, object: nil)
        buildInterface()
        preview.onWidgetSelection = { [weak self] kind in
            guard let self else { return }
            self.modulePopup.selectItem(at: WidgetKind.selectableCases.firstIndex(of: kind.canonical) ?? 0)
            self.selectModule()
            self.selectSection(1)
        }
        sync(config: config)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func present(config: BarConfig) {
        sync(config: config)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func sync(config: BarConfig) {
        self.config = config
        for (id, button) in providerButtons { button.state = config.providerPreferences.includes(id) ? .on : .off }
        lastCommittedConfig = config
        modePopup.selectItem(at: ["system", "light", "dark"].firstIndex(of: config.themeMode) ?? 0)
        modePopup.isEnabled = config.appearance.isNative
        for button in appearanceButtons { button.state = button.choice == config.appearance ? .on : .off; button.mode = config.themeMode; button.needsDisplay = true }
        appearanceDetail.stringValue = config.appearance.subtitle + (config.appearance.isNative ? " Follows your chosen light or dark appearance." : " Uses its own coordinated palette.")
        coveBorderButton.state = config.visualPreferences.coveScreenBorder ? .on : .off
        coveBorderButton.isEnabled = config.appearance == .cove && config.layout == .rail
        coveBorderButton.toolTip = "Cove Rail only: extend to both screen edges with downward-curving corners."
        densityPopup.selectItem(at: BarDensity.allCases.firstIndex(of: config.visualPreferences.density) ?? 1)
        workspaceAppsButton.state = config.visualPreferences.showsWorkspaceAppIcons ? .on : .off
        for (kind, button) in widgetButtons { button.state = config.rightWidgets.contains(kind) ? .on : .off }
        if let index = DateTimePresentation.allCases.firstIndex(of: config.widgetPreferences.dateTimePresentation) { datePopup.selectItem(at: index) }
        artistButton.state = config.widgetPreferences.nowPlayingShowsArtist ? .on : .off
        hideIdlePlayerButton.state = config.widgetPreferences.nowPlayingHidesWhenIdle ? .on : .off
        weatherLocationButton.state = config.widgetPreferences.weatherShowsLocation ? .on : .off
        weatherLocationField.stringValue = config.weather.locationLabel
        latitudeField.doubleValue = config.weather.latitude
        longitudeField.doubleValue = config.weather.longitude
        if let index = WeatherUnit.allCases.firstIndex(of: config.weather.unit) { weatherUnitPopup.selectItem(at: index) }
        displayPopup.selectItem(at: BarDisplayMode.allCases.firstIndex(of: config.displayMode) ?? 0)
        let refreshValues: [Double] = [1, 2, 5, 10]
        refreshPopup.selectItem(at: refreshValues.enumerated().min(by: { abs($0.element - config.systemUpdateInterval) < abs($1.element - config.systemUpdateInterval) })?.offset ?? 1)
        layoutPopup.selectItem(at: BarLayout.allCases.firstIndex(of: config.layout) ?? 0)
        placementPopup.selectItem(at: WidgetPlacement.allCases.firstIndex(of: config.widgetPlacement) ?? 0)
        integrationPopup.selectItem(at: IntegrationMode.allCases.firstIndex(of: config.integration) ?? 0)
        aerospacePathField.stringValue = config.aerospacePath
        workspaceOrderField.stringValue = config.workspaceNames.joined(separator: ", ")
        fullscreenButton.state = config.hideInFullscreen ? .on : .off
        localSpacesButton.state = config.workspacesOnCurrentDisplay ? .on : .off
        for (id, enabled, popup) in displayControls {
            enabled.state = config.displayOverrides[id]?.enabled == false ? .off : .on
            popup.selectItem(at: config.displayOverrides[id]?.layout.flatMap { BarLayout.allCases.firstIndex(of: $0).map { $0 + 1 } } ?? 0)
        }
        rebuildWidgetOrder()
        syncLaunchAtLogin()
        updateDiagnostics()
        if isWindowLoaded { preview.apply(config: config) }
        undoButton.isEnabled = !undoStack.isEmpty
    }

    func selectSection(_ index: Int) {
        sectionsControl.selectedSegment = index
        sectionChanged()
        window?.contentView?.layoutSubtreeIfNeeded()
    }

    func buildInterface() {
        guard let window else { return }
        let background = NSVisualEffectView()
        background.material = .sidebar
        background.blendingMode = .behindWindow
        background.state = .active
        window.contentView = background

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        background.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: background.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: background.bottomAnchor)
        ])

        let document = FlippedSettingsView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -24)
        ])

        let title = NSTextField(labelWithString: "Arrange your desktop.")
        title.font = .systemFont(ofSize: 22, weight: .bold)
        stack.addArrangedSubview(title)
        let subtitle = NSTextField(wrappingLabelWithString: "Choose a layout, then click a module in the preview to configure it. Changes appear live.")
        subtitle.textColor = .secondaryLabelColor
        stack.addArrangedSubview(subtitle)

        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.widthAnchor.constraint(greaterThanOrEqualToConstant: 590).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 76).isActive = true
        stack.addArrangedSubview(preview)

        let historyControls = NSStackView()
        historyControls.orientation = .horizontal
        historyControls.spacing = 8
        undoButton.target = self
        undoButton.action = #selector(undoLastChange)
        undoButton.isEnabled = false
        resetAppearanceButton.target = self
        resetAppearanceButton.action = #selector(resetAppearance)
        historyControls.addArrangedSubview(undoButton)
        historyControls.addArrangedSubview(resetAppearanceButton)
        stack.addArrangedSubview(historyControls)

        sectionsControl.target = self
        sectionsControl.action = #selector(sectionChanged)
        sectionsControl.selectedSegment = 0
        stack.addArrangedSubview(sectionsControl)
        buildLayoutSettings(in: stack)
        buildAppearanceSettings(in: stack)
        buildWidgetsSettings(in: stack)
        buildConnectionsSettings(in: stack)
        buildApplicationSettings(in: stack)
        let weatherNote = NSTextField(wrappingLabelWithString: "Weather uses Open-Meteo and refreshes at most every 10 minutes. Enter WGS84 latitude and longitude for your location.")
        weatherNote.textColor = .tertiaryLabelColor
        weatherNote.font = .systemFont(ofSize: 11)
        stack.addArrangedSubview(weatherNote)
        sections[1, default: []].append(weatherNote)
        for views in sections.values {
            for view in views { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        }
        sectionChanged()
    }

    func syncLaunchAtLogin() {
        launchAtLoginButton.allowsMixedState = true
        launchAtLoginButton.state = LaunchAtLogin.controlState
        launchAtLoginButton.isEnabled = LaunchAtLogin.isRunningFromAppBundle
        launchAtLoginButton.toolTip = LaunchAtLogin.statusDescription
    }

    @objc func updateDiagnostics() {
        aerospaceStatus.stringValue = IntegrationDiagnostics.workspace
        let tailscale = ExecutableDiscovery.find("tailscale")
        tailscaleStatus.stringValue = tailscale.map { "Available · \($0)" } ?? "CLI unavailable · system VPN status available"
        let runningIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        var players = [("com.apple.Music", "Apple Music")].compactMap { runningIDs.contains($0.0) ? $0.1 : nil }
        let browserSessions = BrowserMediaIntegration().sessions().sessions.count
        if browserSessions > 0 { players.append("Browser · \(browserSessions) session(s)") }
        mediaStatus.stringValue = players.isEmpty ? "No supported player running" : players.joined(separator: ", ")
        weatherStatus.stringValue = config.weather.isConfigured ? "Configured · \(config.weather.locationLabel)" : "Optional · choose a location to enable"
        configPathStatus.stringValue = ConfigurationStore.lastError ?? ConfigFile.writableURL().path
    }

    @objc func modeChanged() {
        config.themeMode = ["system", "light", "dark"][max(0, modePopup.indexOfSelectedItem)]
        commit()
        sync(config: config)
    }

    @objc func visualChanged() {
        config.visualPreferences.coveScreenBorder = coveBorderButton.state == .on
        config.visualPreferences.showsWorkspaceAppIcons = workspaceAppsButton.state == .on
        config.visualPreferences.density = BarDensity.allCases[max(0, densityPopup.indexOfSelectedItem)]
        commit()
    }

    @objc func appearanceChanged(_ sender: AppearanceChoiceButton) {
        config.appearance = sender.choice
        commit()
        sync(config: config)
    }

    @objc func widgetVisibilityChanged(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let kind = WidgetKind(rawValue: raw) else { return }
        if sender.state == .on {
            if !config.rightWidgets.contains(kind) { config.rightWidgets.append(kind) }
        } else {
            config.rightWidgets.removeAll { $0 == kind }
        }
        commit()
    }

    @objc func widgetOptionChanged() {
        if datePopup.indexOfSelectedItem >= 0 { config.widgetPreferences.dateTimePresentation = DateTimePresentation.allCases[datePopup.indexOfSelectedItem] }
        if weatherUnitPopup.indexOfSelectedItem >= 0 { config.weather.unit = WeatherUnit.allCases[weatherUnitPopup.indexOfSelectedItem] }
        config.widgetPreferences.nowPlayingShowsArtist = artistButton.state == .on
        config.widgetPreferences.nowPlayingHidesWhenIdle = hideIdlePlayerButton.state == .on
        config.widgetPreferences.weatherShowsLocation = weatherLocationButton.state == .on
        commit()
    }

    @objc func applicationOptionChanged() {
        config.hideInFullscreen = fullscreenButton.state == .on
        config.workspacesOnCurrentDisplay = localSpacesButton.state == .on
        if displayPopup.indexOfSelectedItem >= 0 { config.displayMode = BarDisplayMode.allCases[displayPopup.indexOfSelectedItem] }
        let refreshValues: [Double] = [1, 2, 5, 10]
        if refreshPopup.indexOfSelectedItem >= 0 { config.systemUpdateInterval = refreshValues[refreshPopup.indexOfSelectedItem] }
        commit()
    }

    @objc func launchAtLoginChanged() {
        if LaunchAtLogin.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            syncLaunchAtLogin()
            return
        }
        do {
            try LaunchAtLogin.setEnabled(launchAtLoginButton.state == .on)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn’t Change Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.beginSheetModal(for: window!)
        }
        syncLaunchAtLogin()
    }

    @objc func applicationDidBecomeActive() {
        syncLaunchAtLogin()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if let field = obj.object as? NSTextField, field === aerospacePathField || field === workspaceOrderField {
            config.aerospacePath = aerospacePathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            config.workspaceNames = workspaceOrderField.stringValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            commit()
            return
        }
        config.weather.locationLabel = weatherLocationField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let latitude = Double(latitudeField.stringValue), (-90...90).contains(latitude) { config.weather.latitude = latitude }
        if let longitude = Double(longitudeField.stringValue), (-180...180).contains(longitude) { config.weather.longitude = longitude }
        commit()
        sync(config: config)
    }

    @objc func undoLastChange() {
        guard let previous = undoStack.popLast() else { return }
        config = previous
        lastCommittedConfig = previous
        sync(config: previous)
        onChange(previous)
    }

    @objc func resetAppearance() {
        config.visualPreferences = VisualPreferences(showsWorkspaceAppIcons: config.visualPreferences.showsWorkspaceAppIcons)
        config.appearance = .nativeGlass
        config.themeMode = "system"
        commit()
        sync(config: config)
    }

    func commit() {
        do { try config.validate() } catch { ConfigurationStore.report(error.localizedDescription); config = lastCommittedConfig; sync(config: config); return }
        rebuildWidgetOrder()
        if config.jsonString() != lastCommittedConfig.jsonString() {
            undoStack.append(lastCommittedConfig)
            if undoStack.count > 30 { undoStack.removeFirst(undoStack.count - 30) }
            lastCommittedConfig = config
        }
        undoButton.isEnabled = !undoStack.isEmpty
        preview.apply(config: config)
        onChange(config)
    }

    @objc func selectModule() {
        let selected = WidgetKind.selectableCases[max(0, modulePopup.indexOfSelectedItem)]
        for (kinds, row) in moduleRows { row.isHidden = !kinds.contains(selected) }
        noModuleOptions.isHidden = moduleRows.contains { $0.0.contains(selected) }
    }
    @objc func sectionChanged() {
        for (index, views) in sections { views.forEach { $0.isHidden = index != sectionsControl.selectedSegment } }
    }
    @objc func layoutChanged() {
        config.layout = BarLayout.allCases[max(0, layoutPopup.indexOfSelectedItem)]
        config.widgetPlacement = WidgetPlacement.allCases[max(0, placementPopup.indexOfSelectedItem)]
        commit()
        sync(config: config)
    }
    @objc func providerChanged(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        config.providerPreferences.disabled.removeAll { $0 == id }
        if sender.state == .off { config.providerPreferences.disabled.append(id) }
        commit()
    }
    @objc func connectionChanged() {
        config.integration = IntegrationMode.allCases[max(0, integrationPopup.indexOfSelectedItem)]
        commit()
    }
    @objc func displayChanged() {
        for (id, enabled, popup) in displayControls {
            var override = config.displayOverrides[id] ?? DisplayOverride()
            override.enabled = enabled.state == .on
            override.layout = popup.indexOfSelectedItem > 0 ? BarLayout.allCases[popup.indexOfSelectedItem - 1] : nil
            config.displayOverrides[id] = override
        }
        commit()
    }
    func rebuildWidgetOrder() {
        orderedWidgets.arrangedSubviews.forEach { orderedWidgets.removeArrangedSubview($0); $0.removeFromSuperview() }
        for (index, kind) in config.rightWidgets.enumerated() {
            let label = NSTextField(labelWithString: "\(index + 1)   \(kind.menuTitle)")
            label.widthAnchor.constraint(equalToConstant: 210).isActive = true
            let earlier = NSButton(title: "←", target: self, action: #selector(moveModule(_:)))
            let later = NSButton(title: "→", target: self, action: #selector(moveModule(_:)))
            earlier.tag = index * 2; later.tag = index * 2 + 1
            earlier.isEnabled = index > 0; later.isEnabled = index < config.rightWidgets.count - 1
            earlier.setAccessibilityLabel("Move \(kind.menuTitle) earlier")
            later.setAccessibilityLabel("Move \(kind.menuTitle) later")
            orderedWidgets.addArrangedSubview(NSStackView(views: [label, earlier, later]))
        }
        if config.rightWidgets.isEmpty { orderedWidgets.addArrangedSubview(NSTextField(labelWithString: "Add modules from the Widgets tab.")) }
    }
    @objc func moveModule(_ sender: NSButton) {
        let index = sender.tag / 2, destination = sender.tag / 2 + (sender.tag % 2 == 0 ? -1 : 1)
        guard config.rightWidgets.indices.contains(destination) else { return }
        config.rightWidgets.swapAt(index, destination)
        commit()
    }
    @objc func importConfiguration() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { config = try BarConfig.decode(Data(contentsOf: url)); commit(); sync(config: config) }
        catch { ConfigurationStore.report(error.localizedDescription) }
    }
    @objc func exportConfiguration() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "constellation-config.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        ConfigurationStore.save(config, to: url)
    }
}
