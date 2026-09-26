import AppKit
import ServiceManagement
import UniformTypeIdentifiers

final class FlippedSettingsView: NSView {
    override var isFlipped: Bool { true }
}

final class ConfigurationWindowController: NSWindowController, NSTextFieldDelegate {
    var config: BarConfig
    let onChange: (BarConfig) -> Void
    let persist: (BarConfig) -> ConfigurationSaveResult
    private(set) var unsavedError: String?
    private var pendingUndo = false
    let saveStatus = NSTextField(wrappingLabelWithString: "Changes save automatically.")
    let retrySaveButton = NSButton(title: "Retry Save", target: nil, action: nil)
    let revertSaveButton = NSButton(title: "Revert Unsaved Changes", target: nil, action: nil)
    var undoStack: [BarConfig] = []
    var lastCommittedConfig: BarConfig
    let undoButton = NSButton(title: "Undo", target: nil, action: nil)
    let resetAppearanceButton = NSButton(title: "Reset Appearance", target: nil, action: nil)

    static let sectionTitles = ["Layout", "Widgets", "Appearance", "Application", "Diagnostics"]
    static let sectionDescriptions = [
        "Set the size and layout of the bar on the selected display.",
        "Arrange widgets on the selected display and configure each widget’s behavior and providers.",
        "Choose the appearance of the bar on the selected display.",
        "Manage startup, refresh frequency, and configuration files.",
        "See live provider health, resolve setup issues, and copy a diagnostic report."
    ]
    var selectedSection = 0
    var buildingSection = 0
    var sidebarButtons: [NSButton] = []
    let sectionTitle = NSTextField(labelWithString: "")
    let sectionDescription = NSTextField(wrappingLabelWithString: "")
    let settingsScroll = NSScrollView()
    var sections: [Int: [NSView]] = [:]
    let barPresentationPopup = NSPopUpButton()
    let widgetAlignmentPopup = NSPopUpButton()
    let integrationPopup = NSPopUpButton()
    let aerospacePathField = NSTextField()
    let workspaceOrderField = NSTextField()
    let fullscreenButton = NSButton(checkboxWithTitle: "Hide on the display containing a fullscreen window", target: nil, action: nil)
    let localSpacesButton = NSButton(checkboxWithTitle: "Show each display’s own workspaces", target: nil, action: nil)
    let modulePopup = NSPopUpButton()
    let calendarProviderPopup = NSPopUpButton()
    var providerButtons: [String: NSButton] = [:]
    var moduleRows: [(BarItem, NSView)] = []
    var configurableItems: [BarItem] {
        moduleRows.reduce(into: []) { items, row in
            if !items.contains(row.0) { items.append(row.0) }
        }
    }
    var widgetOptionsSection: NSView?
    let widgetScopeNote = NSTextField(wrappingLabelWithString: "")
    let displayEditor = DisplaySettingsEditor()
    let widgetEditor = DisplaySettingsEditor(widgetsOnly: true)
    let editingDisplayPopup = NSPopUpButton()
    var editingDisplayIDs: [String] = []
    var editingDisplayID: String?
    var displayScopeRow: NSView?
    var previewHeight: NSLayoutConstraint?
    lazy var livePreview = ConfigurationPreviewView(config: config)
    var displayConfig: BarConfig { editingDisplayID.map { config.forDisplay($0) } ?? config }

    func editDisplay(_ edit: (inout DisplayOverride) -> Void, shared: (inout BarConfig) -> Void) {
        if let id = editingDisplayID {
            var value = config.displayOverrides[id] ?? DisplayOverride()
            edit(&value)
            config.displayOverrides[id] = value
        } else { shared(&config) }
    }

    func syncEditingDisplay() {
        let screens = NSScreen.screens
        editingDisplayIDs = screens.map(\.configurationID)
        editingDisplayIDs += config.displayOverrides.keys.filter { !editingDisplayIDs.contains($0) }.sorted()
        if editingDisplayID == nil || !editingDisplayIDs.contains(editingDisplayID!) { editingDisplayID = editingDisplayIDs.first }
        editingDisplayPopup.removeAllItems()
        editingDisplayPopup.addItems(withTitles: editingDisplayIDs.enumerated().map { index, id in
            if let screen = screens.first(where: { $0.configurationID == id }) { return "Display \(index + 1) · \(screen.localizedName)" }
            return "Disconnected display · \(id.prefix(8))"
        })
        if let id = editingDisplayID, let index = editingDisplayIDs.firstIndex(of: id) { editingDisplayPopup.selectItem(at: index) }
        editingDisplayPopup.isEnabled = !editingDisplayIDs.isEmpty
        livePreview.apply(config: displayConfig)
    }

    @objc func editingDisplayChanged() {
        guard editingDisplayIDs.indices.contains(editingDisplayPopup.indexOfSelectedItem) else { return }
        editingDisplayID = editingDisplayIDs[editingDisplayPopup.indexOfSelectedItem]
        sync(config: config)
    }
    var appearanceButtons: [AppearanceChoiceButton] = []
    let nativeColorPopup = NSPopUpButton()
    let typesetSchemePopup = NSPopUpButton()
    let typesetVariantPopup = NSPopUpButton()
    let appearanceDetail = NSTextField(wrappingLabelWithString: "")
    let modePopup = NSPopUpButton()
    let coveBorderButton = NSButton(checkboxWithTitle: "Full-width screen border", target: nil, action: nil)
    let coveCornerRadiusSlider = NSSlider(value: 12, minValue: 0, maxValue: 40, target: nil, action: nil)
    let coveCornerRadiusLabel = NSTextField(labelWithString: "12 pt")
    let densityPopup = NSPopUpButton()
    let workspaceAppsButton = NSButton(checkboxWithTitle: "Show open application icons", target: nil, action: nil)
    let worldClocksField = NSTextField()
    let timerPresetsField = NSTextField()
    var reminderListButtons: [String: NSButton] = [:]
    let reminderListChoices = NSStackView()
    let reminderAccessReader = AppleRemindersReader()
    let datePopup = NSPopUpButton()
    var systemMetricButtons: [SystemMetric: NSButton] = [:]
    let systemGraphButton = NSButton(checkboxWithTitle: "Show CPU graph", target: nil, action: nil)
    let compositionPopup = NSPopUpButton()
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
    let launchAtLoginStatus = NSTextField(wrappingLabelWithString: "")
    let updateStatus = NSTextField(wrappingLabelWithString: "")
    let checkUpdatesButton = NSButton(title: "Check for Updates…", target: nil, action: nil)
    let diagnosticsFreshness = NSTextField(labelWithString: "Waiting for the first sample…")
    let configErrorStatus = NSTextField(wrappingLabelWithString: "")
    var diagnosticRows: [WidgetKind: DiagnosticRow] = [:]
    var workspaceDiagnosticRow: DiagnosticRow?
    let configPathStatus = NSTextField(labelWithString: "")

    init(config: BarConfig, persist: @escaping (BarConfig) -> ConfigurationSaveResult = { _ in .saved(URL(fileURLWithPath: "/dev/null")) }, onChange: @escaping (BarConfig) -> Void) {
        self.config = config
        self.lastCommittedConfig = config
        self.onChange = onChange
        self.persist = persist
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
        NotificationCenter.default.addObserver(self, selector: #selector(syncUpdater), name: AppUpdater.changed, object: nil)
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
        if unsavedError == nil, let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) { editingDisplayID = screen.configurationID }
        sync(config: config)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func sync(config: BarConfig) {
        // External refreshes must not erase a failed-save draft.
        if unsavedError != nil, config.jsonString() != self.config.jsonString() { return }
        self.config = config
        syncEditingDisplay()
        let local = displayConfig
        syncSystemOptions()
        compositionPopup.selectItem(at: BarLayout.allCases.firstIndex(of: local.layout) ?? 0)
        calendarProviderPopup.selectItem(at: CalendarProviderChoice.allCases.firstIndex(of: config.providerPreferences.calendarProvider) ?? 0)
        for (id, button) in providerButtons { button.state = config.providerPreferences.includes(id) ? .on : .off }
        if unsavedError == nil { lastCommittedConfig = config }
        modePopup.selectItem(at: ["system", "light", "dark"].firstIndex(of: local.themeMode) ?? 0)
        syncAppearanceControls(local)
        coveBorderButton.state = local.visualPreferences.coveScreenBorder ? .on : .off
        coveCornerRadiusSlider.doubleValue = local.visualPreferences.coveCornerRadius
        coveCornerRadiusLabel.stringValue = "\(Int(local.visualPreferences.coveCornerRadius)) pt"
        coveBorderButton.isEnabled = local.appearance == .cove && local.layout == .rail
        coveBorderButton.toolTip = "Cove Rail only: extend to both screen edges with downward-curving corners."
        densityPopup.selectItem(at: BarDensity.allCases.firstIndex(of: local.visualPreferences.density) ?? 1)
        workspaceAppsButton.state = local.visualPreferences.showsWorkspaceAppIcons ? .on : .off
        if let index = DateTimePresentation.allCases.firstIndex(of: config.widgetPreferences.dateTimePresentation) { datePopup.selectItem(at: index) }
        syncDailyWidgetSettings()
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
        barPresentationPopup.selectItem(at: BarPresentation.allCases.firstIndex(of: local.barPresentation) ?? 0)
        widgetAlignmentPopup.selectItem(at: WidgetAlignment.allCases.firstIndex(of: local.widgetLayout.alignment) ?? 1)
        integrationPopup.selectItem(at: IntegrationMode.allCases.firstIndex(of: config.integration) ?? 0)
        aerospacePathField.stringValue = config.aerospacePath
        workspaceOrderField.stringValue = config.workspaceNames.joined(separator: ", ")
        fullscreenButton.state = config.hideInFullscreen ? .on : .off
        localSpacesButton.state = config.workspacesOnCurrentDisplay ? .on : .off
        displayEditor.sync(config: config)
        displayEditor.selectDisplay(id: editingDisplayID)
        widgetEditor.sync(config: config)
        widgetEditor.selectDisplay(id: editingDisplayID)
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
        let symbols = ["display.2", "square.grid.2x2", "paintpalette", "gearshape", "waveform.path.ecg"]
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
        saveStatus.font = .systemFont(ofSize: 11)
        saveStatus.maximumNumberOfLines = 5
        sidebar.addArrangedSubview(saveStatus)
        saveStatus.widthAnchor.constraint(equalTo: sidebar.widthAnchor).isActive = true
        retrySaveButton.target = self; retrySaveButton.action = #selector(retrySave)
        revertSaveButton.target = self; revertSaveButton.action = #selector(revertUnsaved)
        sidebar.addArrangedSubview(retrySaveButton)
        sidebar.addArrangedSubview(revertSaveButton)
        updateSaveStatus()

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
        editingDisplayPopup.target = self
        editingDisplayPopup.action = #selector(editingDisplayChanged)
        let scope = formRow("Editing display", editingDisplayPopup)
        displayScopeRow = scope
        stack.addArrangedSubview(scope)
        livePreview.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(livePreview)
        livePreview.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        previewHeight = livePreview.heightAnchor.constraint(equalToConstant: 86)
        previewHeight?.isActive = true
        livePreview.onWidgetSelection = { [weak self] kind in
            self?.selectWidgetOptions(.widget(kind))
        }
        buildingSection = 0
        buildLayoutSettings(in: stack)
        buildingSection = 1
        buildWidgetsSettings(in: stack)
        buildingSection = 2
        buildAppearanceSettings(in: stack)
        buildingSection = 3
        buildApplicationSettings(in: stack)
        buildingSection = 4
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
        launchAtLoginStatus.stringValue = LaunchAtLogin.statusDescription
        launchAtLoginStatus.textColor = LaunchAtLogin.status == .requiresApproval || LaunchAtLogin.lastError != nil ? .systemOrange : .secondaryLabelColor
    }

    @objc func updateDiagnostics() {
        if let date = IntegrationDiagnostics.sampledAt {
            let age = max(0, Int(Date().timeIntervalSince(date)))
            let stale = Double(age) > max(10, config.systemUpdateInterval * 3)
            diagnosticsFreshness.stringValue = "\(stale ? "Sample is stale" : "Last provider sample"): \(date.formatted(date: .omitted, time: .standard)) · \(age)s ago · refresh interval \(Int(config.systemUpdateInterval))s"
            diagnosticsFreshness.textColor = stale ? .systemOrange : .secondaryLabelColor
        } else { diagnosticsFreshness.stringValue = "Waiting for the first provider sample. Hidden widgets are not sampled." }
        let workspaceHealth: DiagnosticEntry.Health = config.integration == .standalone ? .ready
            : IntegrationDiagnostics.workspace == "Checking integrations…" ? .pending
            : IntegrationDiagnostics.workspace == "AeroSpace connected" ? .ready : .attention
        workspaceDiagnosticRow?.apply(DiagnosticEntry(title: "Workspaces", health: workspaceHealth,
            detail: config.integration == .standalone ? "Standalone mode · uses the active application." : IntegrationDiagnostics.workspace, widget: nil))
        for entry in diagnosticEntries() { if let kind = entry.widget { diagnosticRows[kind]?.apply(entry) } }
        configPathStatus.stringValue = ConfigFile.writableURL().path
        configPathStatus.toolTip = configPathStatus.stringValue
        configErrorStatus.stringValue = ConfigurationStore.diagnosticError ?? "No configuration errors reported. Changes save automatically; Undo is available in the sidebar."
        configErrorStatus.textColor = ConfigurationStore.diagnosticError == nil ? .secondaryLabelColor : .systemOrange
    }

    @objc func modeChanged() {
        let mode = ["system", "light", "dark"][max(0, modePopup.indexOfSelectedItem)]
        editDisplay({ $0.themeMode = mode }, shared: { $0.themeMode = mode })
        commit()
    }

    @objc func visualChanged() {
        var visuals = displayConfig.visualPreferences
        visuals.coveScreenBorder = coveBorderButton.state == .on
        visuals.coveCornerRadius = coveCornerRadiusSlider.doubleValue.rounded()
        visuals.density = BarDensity.allCases[max(0, densityPopup.indexOfSelectedItem)]
        editDisplay({ $0.visualPreferences = visuals }, shared: { $0.visualPreferences = visuals })
        commit()
    }

    @objc func appearanceChanged(_ sender: AppearanceChoiceButton) {
        let appearance = sender.choice.family == .native && displayConfig.appearance.family == .native ? displayConfig.appearance : sender.choice
        editDisplay({ $0.appearance = appearance }, shared: { $0.appearance = appearance })
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
        if displayPopup.indexOfSelectedItem >= 0 { config.displayMode = BarDisplayMode.allCases[displayPopup.indexOfSelectedItem] }
        let refreshValues: [Double] = [1, 2, 5, 10]
        if refreshPopup.indexOfSelectedItem >= 0 { config.systemUpdateInterval = refreshValues[refreshPopup.indexOfSelectedItem] }
        commit()
    }

    @objc func launchAtLoginChanged() {
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
        if let field = obj.object as? NSTextField, field === worldClocksField || field === timerPresetsField { dailyWidgetFieldsChanged(); return }
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
    }

    @objc func undoLastChange() {
        guard unsavedError == nil, let previous = undoStack.last else { return }
        config = previous; pendingUndo = true
        commit()
    }
    @objc func retrySave() { commit() }
    @objc func revertUnsaved() {
        unsavedError = nil; pendingUndo = false
        config = lastCommittedConfig; sync(config: config); updateSaveStatus()
    }
    private func updateSaveStatus() {
        saveStatus.stringValue = unsavedError.map { "Not saved. The desktop still uses your saved settings. \($0)" } ?? "All changes saved."
        saveStatus.textColor = unsavedError == nil ? .secondaryLabelColor : .systemRed
        saveStatus.toolTip = unsavedError
        retrySaveButton.isHidden = unsavedError == nil
        revertSaveButton.isHidden = unsavedError == nil
        undoButton.isEnabled = unsavedError == nil && !undoStack.isEmpty
    }

    @objc func resetAppearance() {
        let visuals = VisualPreferences(showsWorkspaceAppIcons: displayConfig.visualPreferences.showsWorkspaceAppIcons)
        editDisplay({ $0.visualPreferences = visuals; $0.appearance = .nativeGlass; $0.typesetScheme = .graphite; $0.typesetVariant = "default"; $0.themeMode = "system" },
                    shared: { $0.visualPreferences = visuals; $0.appearance = .nativeGlass; $0.typesetScheme = .graphite; $0.typesetVariant = "default"; $0.themeMode = "system" })
        commit()
    }

    func commit() {
        if pendingUndo, config.jsonString() != undoStack.last?.jsonString() { pendingUndo = false }
        do { try config.validate() } catch {
            unsavedError = error.localizedDescription; updateSaveStatus(); return
        }
        let result = persist(config)
        guard result.succeeded else {
            unsavedError = result.error
            // Refresh draft controls, but retain the saved baseline and undo history.
            sync(config: config); updateSaveStatus(); return
        }
        if pendingUndo { _ = undoStack.popLast() }
        else if config.jsonString() != lastCommittedConfig.jsonString() {
            undoStack.append(lastCommittedConfig)
            if undoStack.count > 30 { undoStack.removeFirst(undoStack.count - 30) }
        }
        pendingUndo = false; unsavedError = nil
        lastCommittedConfig = config
        sync(config: config); updateSaveStatus()
        onChange(config)
    }

    @objc func selectModule() {
        guard configurableItems.indices.contains(modulePopup.indexOfSelectedItem) else { return }
        let selected = configurableItems[modulePopup.indexOfSelectedItem]
        widgetScopeNote.stringValue = selected == .workspaces
            ? "Source, order and shared visibility apply to all displays. Display visibility and application icons use the selected display."
            : "These settings apply to all displays."
        for (item, row) in moduleRows { row.isHidden = item != selected }
    }
    func selectWidgetOptions(_ item: BarItem) {
        guard let index = configurableItems.firstIndex(of: item) else { return }
        selectSection(1)
        modulePopup.selectItem(at: index)
        selectModule()
        window?.contentView?.layoutSubtreeIfNeeded()
        if let section = widgetOptionsSection { section.scrollToVisible(section.bounds) }
    }
    @objc func sidebarSelected(_ sender: NSButton) { selectSection(sender.tag) }
    @objc func sectionChanged() {
        for (index, views) in sections { views.forEach { $0.isHidden = index != selectedSection } }
        for button in sidebarButtons {
            button.state = button.tag == selectedSection ? .on : .off
            button.layer?.backgroundColor = button.tag == selectedSection
                ? NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor : NSColor.clear.cgColor
        }
        previewHeight?.isActive = selectedSection < 3
        displayScopeRow?.isHidden = selectedSection >= 3
        livePreview.isHidden = selectedSection >= 3
        sectionTitle.stringValue = Self.sectionTitles[selectedSection]
        sectionDescription.stringValue = Self.sectionDescriptions[selectedSection]
        window?.contentView?.layoutSubtreeIfNeeded()
        if selectedSection == 4 { updateDiagnostics() }
        settingsScroll.contentView.scroll(to: .zero)
        settingsScroll.reflectScrolledClipView(settingsScroll.contentView)
    }
    @objc func layoutChanged() {
        let presentation = BarPresentation.allCases[max(0, barPresentationPopup.indexOfSelectedItem)]
        let composition: BarLayout = presentation == .fullWidth ? .rail : (displayConfig.layout == .compact ? .compact : .islands)
        var zones = displayConfig.widgetLayout
        zones.alignment = WidgetAlignment.allCases[max(0, widgetAlignmentPopup.indexOfSelectedItem)]
        editDisplay({ $0.barPresentation = presentation; $0.layout = composition; $0.widgetLayout = zones },
                    shared: { $0.barPresentation = presentation; $0.layout = composition; $0.setWidgetLayout(zones) })
        commit()
    }

    @objc func providerChanged(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        config.providerPreferences.disabled.removeAll { $0 == id }
        if sender.state == .off { config.providerPreferences.disabled.append(id) }
        commit()
    }
    @objc func workspaceSourceChanged() {
        config.integration = IntegrationMode.allCases[max(0, integrationPopup.indexOfSelectedItem)]
        commit()
    }
    @objc func displaysChanged() { sync(config: config) }
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
