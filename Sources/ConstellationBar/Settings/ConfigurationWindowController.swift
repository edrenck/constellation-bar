import AppKit
import ServiceManagement
import UniformTypeIdentifiers

final class FlippedSettingsView: NSView {
    override var isFlipped: Bool { true }
}

final class ConfigurationWindowController: NSWindowController, NSTextFieldDelegate {
    var config: BarConfig
    let onChange: (BarConfig) -> Void
    var undoStack: [BarConfig] = []
    var lastCommittedConfig: BarConfig
    let undoButton = NSButton(title: "Undo", target: nil, action: nil)
    let resetAppearanceButton = NSButton(title: "Reset Appearance", target: nil, action: nil)

    static let sectionTitles = ["Displays", "Widgets", "Appearance", "Workspaces", "Connections", "Application", "Diagnostics"]
    static let sectionDescriptions = [
        "Choose a display and arrange its bar. Display overrides take precedence over shared defaults.",
        "Choose default widgets for displays without a custom arrangement. Widget options apply everywhere.",
        "Set the shared appearance. Displays with a custom theme keep their own settings.",
        "Choose your workspace source, ordering, and app icons.",
        "Choose which services supply widget data. Arrange visible widgets in Displays.",
        "Manage startup, refresh frequency, and configuration files.",
        "Check integration availability and the configuration file location."
    ]
    var selectedSection = 0
    var buildingSection = 0
    var sidebarButtons: [NSButton] = []
    let sectionTitle = NSTextField(labelWithString: "")
    let sectionDescription = NSTextField(wrappingLabelWithString: "")
    let settingsScroll = NSScrollView()
    var sections: [Int: [NSView]] = [:]
    let layoutPopup = NSPopUpButton()
    let placementPopup = NSPopUpButton()
    let barPresentationPopup = NSPopUpButton()
    let widgetAlignmentPopup = NSPopUpButton()
    let integrationPopup = NSPopUpButton()
    let aerospacePathField = NSTextField()
    let workspaceOrderField = NSTextField()
    let fullscreenButton = NSButton(checkboxWithTitle: "Hide on the display containing a fullscreen window", target: nil, action: nil)
    let localSpacesButton = NSButton(checkboxWithTitle: "Show each display’s own workspaces", target: nil, action: nil)
    let orderedWidgets = NSStackView()
    let modulePopup = NSPopUpButton()
    let calendarProviderPopup = NSPopUpButton()
    var providerButtons: [String: NSButton] = [:]
    var moduleRows: [(Set<WidgetKind>, NSView)] = []
    let noModuleOptions = NSTextField(labelWithString: "This module uses your system settings.")
    let displayEditor = DisplaySettingsEditor()
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
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Customize ConstellationBar"
        window.minSize = NSSize(width: 980, height: 640)
        window.collectionBehavior = [.moveToActiveSpace]
        super.init(window: window)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActive), name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateDiagnostics), name: IntegrationDiagnostics.changed, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        buildInterface()
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
        calendarProviderPopup.selectItem(at: CalendarProviderChoice.allCases.firstIndex(of: config.providerPreferences.calendarProvider) ?? 0)
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
        for (kind, button) in widgetButtons {
            button.state = config.widgetLayout.allWidgetKinds.contains { $0.canonical == kind } ? .on : .off
        }
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
        barPresentationPopup.selectItem(at: BarPresentation.allCases.firstIndex(of: config.barPresentation) ?? 0)
        widgetAlignmentPopup.selectItem(at: WidgetAlignment.allCases.firstIndex(of: config.widgetLayout.alignment) ?? 1)
        integrationPopup.selectItem(at: IntegrationMode.allCases.firstIndex(of: config.integration) ?? 0)
        aerospacePathField.stringValue = config.aerospacePath
        workspaceOrderField.stringValue = config.workspaceNames.joined(separator: ", ")
        fullscreenButton.state = config.hideInFullscreen ? .on : .off
        localSpacesButton.state = config.workspacesOnCurrentDisplay ? .on : .off
        displayEditor.sync(config: config)
        rebuildWidgetOrder()
        syncLaunchAtLogin()
        updateDiagnostics()
        undoButton.isEnabled = !undoStack.isEmpty
    }

    func selectSection(_ index: Int) {
        guard Self.sectionTitles.indices.contains(index) else { return }
        window?.makeFirstResponder(nil)
        selectedSection = index
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

        let sidebar = NSStackView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.orientation = .vertical
        sidebar.alignment = .leading
        sidebar.spacing = 6
        background.addSubview(sidebar)
        let brand = NSTextField(labelWithString: "ConstellationBar")
        brand.font = .systemFont(ofSize: 16, weight: .semibold)
        sidebar.addArrangedSubview(brand)
        sidebar.setCustomSpacing(22, after: brand)
        let symbols = ["display.2", "square.grid.2x2", "paintpalette", "rectangle.3.group", "link", "gearshape", "waveform.path.ecg"]
        for (index, title) in Self.sectionTitles.enumerated() {
            let button = NSButton(title: title, target: self, action: #selector(sidebarSelected(_:)))
            button.setButtonType(.pushOnPushOff)
            button.bezelStyle = .regularSquare
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 7
            button.alignment = .left
            button.image = NSImage(systemSymbolName: symbols[index], accessibilityDescription: nil)
            button.imagePosition = .imageLeading
            button.tag = index
            button.font = .systemFont(ofSize: 14, weight: .medium)
            sidebar.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: sidebar.widthAnchor).isActive = true
            button.heightAnchor.constraint(equalToConstant: 36).isActive = true
            sidebarButtons.append(button)
        }
        let liveNote = NSTextField(wrappingLabelWithString: "Changes apply immediately to your desktop bar.")
        liveNote.font = .systemFont(ofSize: 12)
        liveNote.textColor = .secondaryLabelColor
        sidebar.addArrangedSubview(liveNote)
        liveNote.widthAnchor.constraint(equalTo: sidebar.widthAnchor).isActive = true
        sidebar.setCustomSpacing(22, after: sidebarButtons.last!)
        undoButton.target = self
        undoButton.action = #selector(undoLastChange)
        sidebar.addArrangedSubview(undoButton)

        let scroll = settingsScroll
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .windowBackgroundColor
        background.addSubview(scroll)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 16),
            sidebar.topAnchor.constraint(equalTo: background.topAnchor, constant: 24),
            sidebar.widthAnchor.constraint(equalToConstant: 190),
            scroll.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 16),
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

        sectionTitle.font = .systemFont(ofSize: 26, weight: .bold)
        sectionDescription.textColor = .secondaryLabelColor
        stack.addArrangedSubview(sectionTitle)
        stack.addArrangedSubview(sectionDescription)
        sectionDescription.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        buildingSection = 0
        buildLayoutSettings(in: stack)
        buildingSection = 1
        buildWidgetsSettings(in: stack)
        buildingSection = 2
        buildAppearanceSettings(in: stack)
        buildingSection = 3
        buildWorkspacesSettings(in: stack)
        buildingSection = 4
        buildConnectionsSettings(in: stack)
        buildingSection = 5
        buildApplicationSettings(in: stack)
        buildingSection = 6
        buildDiagnosticsSettings(in: stack)
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
        mediaStatus.stringValue = config.providerPreferences.includes("nativeMedia") ? "macOS Now Playing · system player" : "macOS Now Playing disabled"
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
        var zones = config.widgetLayout
        for zone in BarZone.allCases { zones.setItems(zones.items(in: zone).filter { $0.widgetKind != kind }, in: zone) }
        if sender.state == .on {
            zones.right.append(.widget(kind))
        }
        config.setWidgetLayout(zones)
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
        displayEditor.sync(config: config)
        onChange(config)
    }

    @objc func selectModule() {
        let selected = WidgetKind.selectableCases[max(0, modulePopup.indexOfSelectedItem)]
        for (kinds, row) in moduleRows { row.isHidden = !kinds.contains(selected) }
        noModuleOptions.isHidden = moduleRows.contains { $0.0.contains(selected) }
    }
    @objc func sidebarSelected(_ sender: NSButton) { selectSection(sender.tag) }
    @objc func sectionChanged() {
        for (index, views) in sections { views.forEach { $0.isHidden = index != selectedSection } }
        for button in sidebarButtons {
            button.state = button.tag == selectedSection ? .on : .off
            button.layer?.backgroundColor = button.tag == selectedSection
                ? NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor : NSColor.clear.cgColor
        }
        sectionTitle.stringValue = Self.sectionTitles[selectedSection]
        sectionDescription.stringValue = Self.sectionDescriptions[selectedSection]
        window?.contentView?.layoutSubtreeIfNeeded()
        settingsScroll.contentView.scroll(to: .zero)
        settingsScroll.reflectScrolledClipView(settingsScroll.contentView)
    }
    @objc func layoutChanged() {
        config.barPresentation = BarPresentation.allCases[max(0, barPresentationPopup.indexOfSelectedItem)]
        var zones = config.widgetLayout
        zones.alignment = WidgetAlignment.allCases[max(0, widgetAlignmentPopup.indexOfSelectedItem)]
        config.layout = config.barPresentation == .fullWidth ? .rail : .islands
        config.widgetPlacement = zones.alignment == .centerAll ? .centered : .trailing
        config.setWidgetLayout(zones)
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
    @objc func displaysChanged() { displayEditor.sync(config: config) }
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
        config.moveGlobalEdgeWidget(from: index, to: destination)
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
