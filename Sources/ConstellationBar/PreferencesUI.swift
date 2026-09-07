import AppKit
import ServiceManagement
import UniformTypeIdentifiers

private final class FlippedSettingsView: NSView {
    override var isFlipped: Bool { true }
}

final class ConfigurationPreviewView: NSView {
    private var config: BarConfig
    private let bar: BarRootView
    var onWidgetSelection: ((WidgetKind) -> Void)?

    init(config: BarConfig) {
        var previewConfig = config
        previewConfig.sideMargin = 10
        self.config = previewConfig
        bar = BarRootView(frame: .zero, config: previewConfig)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        addSubview(bar)
        bar.onWidgetSelection = { [weak self] kind in self?.onWidgetSelection?(kind) }
        bar.render(state: Self.previewState)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let height = config.height + config.coveEdgeDepth
        bar.frame = NSRect(x: 0, y: bounds.midY - height / 2, width: bounds.width, height: height)
    }

    func apply(config: BarConfig) {
        var previewConfig = config
        previewConfig.sideMargin = 10
        self.config = previewConfig
        bar.apply(config: previewConfig)
        bar.render(state: Self.previewState)
        needsLayout = true
    }

    static let previewState: BarState = {
        let finder = WindowIdentity(id: -1, workspace: "1", appName: "Finder", bundleID: "com.apple.finder", title: "Projects")
        let terminal = WindowIdentity(id: -2, workspace: "1", appName: "Terminal", bundleID: "com.apple.Terminal", title: "Build")
        let music = WindowIdentity(id: -3, workspace: "2", appName: "Music", bundleID: "com.apple.Music", title: "Library")
        var system = SystemState()
        system.agents.providers = [AgentProviderSnapshot(id: "codex", name: "Codex", tasks: [.init(id: "preview", activity: .active)], available: true, message: "Preview")]
        system.date = Date(timeIntervalSince1970: 1788714000)
        system.battery = BatteryState(percent: 72, isCharging: false, timeRemainingMinutes: 245, powerSource: "Battery")
        system.network = NetworkSpeedState(downloadBytesPerSecond: 1_800_000, uploadBytesPerSecond: 240_000)
        system.cpu = CPUState(usage: 34)
        system.memory = MemoryState(usage: 58, usedBytes: 19_000_000_000, totalBytes: 32_000_000_000)
        system.nowPlaying = NowPlayingState(title: "Midnight City", artist: "M83", isPlaying: true, source: "Music")
        system.weather = WeatherState(temperature: 78, weatherCode: 1, isDay: true, apparentTemperature: 79, humidity: 31, windSpeed: 8)
        return BarState(
            workspaces: [
                WorkspaceState(name: "1", isFocused: true, windows: [finder, terminal]),
                WorkspaceState(name: "2", isFocused: false, windows: [music]),
                WorkspaceState(name: "3", isFocused: false, windows: [])
            ],
            focusedWindow: finder,
            system: system
        )
    }()
}

final class ConfigurationWindowController: NSWindowController, NSTextFieldDelegate {
    private var config: BarConfig
    private let onChange: (BarConfig) -> Void
    private lazy var preview = ConfigurationPreviewView(config: config)
    private var undoStack: [BarConfig] = []
    private var lastCommittedConfig: BarConfig
    private let undoButton = NSButton(title: "Undo", target: nil, action: nil)
    private let resetAppearanceButton = NSButton(title: "Reset Appearance", target: nil, action: nil)

    private let sectionsControl = NSSegmentedControl(labels: ["Layout", "Widgets", "Appearance", "Connections", "Application"], trackingMode: .selectOne, target: nil, action: nil)
    private var sections: [Int: [NSView]] = [:]
    private let layoutPopup = NSPopUpButton()
    private let placementPopup = NSPopUpButton()
    private let integrationPopup = NSPopUpButton()
    private let aerospacePathField = NSTextField()
    private let workspaceOrderField = NSTextField()
    private let fullscreenButton = NSButton(checkboxWithTitle: "Hide on the display containing a fullscreen window", target: nil, action: nil)
    private let localSpacesButton = NSButton(checkboxWithTitle: "Show each display’s own workspaces", target: nil, action: nil)
    private let orderedWidgets = NSStackView()
    private let modulePopup = NSPopUpButton()
    private var providerButtons: [String: NSButton] = [:]
    private var moduleRows: [(Set<WidgetKind>, NSView)] = []
    private let noModuleOptions = NSTextField(labelWithString: "This module uses your system settings.")
    private var displayControls: [(String, NSButton, NSPopUpButton)] = []
    private var appearanceButtons: [AppearanceChoiceButton] = []
    private let appearanceDetail = NSTextField(wrappingLabelWithString: "")
    private let modePopup = NSPopUpButton()
    private let coveBorderButton = NSButton(checkboxWithTitle: "Full-width screen border", target: nil, action: nil)
    private let densityPopup = NSPopUpButton()
    private let workspaceAppsButton = NSButton(checkboxWithTitle: "Show open application icons", target: nil, action: nil)
    private var widgetButtons: [WidgetKind: NSButton] = [:]
    private let datePopup = NSPopUpButton()
    private let artistButton = NSButton(checkboxWithTitle: "Include artist", target: nil, action: nil)
    private let hideIdlePlayerButton = NSButton(checkboxWithTitle: "Hide when nothing is playing", target: nil, action: nil)
    private let weatherLocationButton = NSButton(checkboxWithTitle: "Show location in bar", target: nil, action: nil)
    private let weatherLocationField = NSTextField()
    private let latitudeField = NSTextField()
    private let longitudeField = NSTextField()
    private let weatherUnitPopup = NSPopUpButton()
    private let displayPopup = NSPopUpButton()
    private let refreshPopup = NSPopUpButton()
    private let launchAtLoginButton = NSButton(checkboxWithTitle: "Launch ConstellationBar at login", target: nil, action: nil)
    private let aerospaceStatus = NSTextField(labelWithString: "")
    private let tailscaleStatus = NSTextField(labelWithString: "")
    private let mediaStatus = NSTextField(labelWithString: "")
    private let weatherStatus = NSTextField(labelWithString: "")
    private let configPathStatus = NSTextField(labelWithString: "")

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

    private func buildInterface() {
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
        configureAppearanceControls()
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
        stack.addArrangedSubview(makeSection(title: "Appearance Studio", rows: [
            gallery, appearanceDetail,
            formRow("Native mode", modePopup),
            formRow("Cove Rail", coveBorderButton),
            formRow("Density", densityPopup),
            formRow("Space contents", workspaceAppsButton)
        ]))

        let widgetGrid = NSGridView(views: widgetRows())
        widgetGrid.rowSpacing = 8
        widgetGrid.columnSpacing = 20
        widgetGrid.xPlacement = .fill
        stack.addArrangedSubview(makeSection(title: "Visible Widgets", rows: [widgetGrid]))

        configureWidgetOptionControls()
        modulePopup.addItems(withTitles: WidgetKind.selectableCases.map(\.menuTitle))
        modulePopup.target = self; modulePopup.action = #selector(selectModule)
        moduleRows = [
            ([.agentStatus], formRow("Monitoring", NSTextField(wrappingLabelWithString: "Codex tasks on this Mac. Active includes waiting for input or approval. Providers can be enabled in Connections."))),
            ([.system], formRow("Metrics", NSTextField(labelWithString: "CPU, memory and network history in one panel."))),
            ([.dateTime], formRow("Date & time", datePopup)),
            ([.nowPlaying], formRow("Artist", artistButton)),
            ([.nowPlaying], formRow("When idle", hideIdlePlayerButton)),
            ([.weather], formRow("Location", weatherLocationButton)),
            ([.weather], formRow("Location label", weatherLocationField)),
            ([.weather], coordinateRow()),
            ([.weather], formRow("Temperature", weatherUnitPopup))
        ]
        stack.addArrangedSubview(makeSection(title: "Widget Options", rows: [formRow("Configure", modulePopup)] + moduleRows.map { $0.1 } + [noModuleOptions]))
        selectModule()

        integrationPopup.addItems(withTitles: IntegrationMode.allCases.map(\.title))
        integrationPopup.target = self
        integrationPopup.action = #selector(connectionChanged)
        aerospacePathField.placeholderString = "Automatic discovery"
        workspaceOrderField.placeholderString = "Automatic · all discovered workspaces"
        aerospacePathField.delegate = self
        workspaceOrderField.delegate = self
        stack.addArrangedSubview(makeSection(title: "Connections", rows: [formRow("Workspace source", integrationPopup), formRow("AeroSpace path", aerospacePathField), formRow("Preferred order", workspaceOrderField), NSTextField(wrappingLabelWithString: "AeroSpace is optional. Automatic mode discovers its CLI and falls back to your active app when unavailable. Preferred order is a comma-separated list; new workspaces remain visible.")]))
        let providerRows: [NSView] = IntegrationCatalog.all.map { descriptor in
            if descriptor.comingLater {
                let label = NSTextField(wrappingLabelWithString: descriptor.title + " · Coming later")
                label.textColor = .secondaryLabelColor
                return label
            }
            let toggle = NSButton(checkboxWithTitle: descriptor.title, target: self, action: #selector(providerChanged(_:)))
            toggle.identifier = NSUserInterfaceItemIdentifier(descriptor.id)
            toggle.toolTip = descriptor.detail
            providerButtons[descriptor.id] = toggle
            return toggle
        }
        let musicAccess = WidgetActionButton("Allow Apple Music access") {
            DispatchQueue.global(qos: .userInitiated).async {
                let allowed = AppleMusicIntegration.authorized(ask: true)
                if !allowed { DispatchQueue.main.async {
                    let alert = NSAlert(); alert.messageText = "Apple Music access is off"
                    alert.informativeText = "Open Music, then allow ConstellationBar in System Settings → Privacy & Security → Automation."
                    alert.runModal()
                } }
            }
        }
        let browserGuide = WidgetActionButton("Browser media setup guide") {
            if let url = Bundle.main.url(forResource: "BrowserMedia-README", withExtension: "md") { NSWorkspace.shared.open(url) }
        }
        stack.addArrangedSubview(makeSection(title: "Widget Providers", rows: providerRows + [musicAccess, browserGuide, NSTextField(wrappingLabelWithString: "Enable widgets in Widgets. Open their panels to grant access or finish setup. Browser media requires the optional companion extension; permissions are per tab.")]))
        configureApplicationControls()
        fullscreenButton.target = self; fullscreenButton.action = #selector(applicationOptionChanged)
        localSpacesButton.target = self; localSpacesButton.action = #selector(applicationOptionChanged)
        stack.addArrangedSubview(makeSection(title: "Application", rows: [
            formRow("Startup", launchAtLoginButton),
            formRow("Displays", displayPopup),
            fullscreenButton, localSpacesButton,
            formRow("System refresh", refreshPopup)
        ]))

        var displayRows: [NSView] = []
        for screen in NSScreen.screens {
            let enabled = NSButton(checkboxWithTitle: screen.localizedName, target: self, action: #selector(displayChanged))
            let popup = NSPopUpButton()
            popup.addItems(withTitles: ["Use global layout"] + BarLayout.allCases.map(\.title))
            popup.target = self; popup.action = #selector(displayChanged)
            displayControls.append((screen.configurationID, enabled, popup))
            let row = NSStackView(views: [enabled, popup])
            row.spacing = 12
            row.toolTip = screen.configurationID
            displayRows.append(row)
        }
        stack.addArrangedSubview(makeSection(title: "Display overrides", rows: displayRows))
        let importButton = NSButton(title: "Import configuration…", target: self, action: #selector(importConfiguration))
        let exportButton = NSButton(title: "Export configuration…", target: self, action: #selector(exportConfiguration))
        stack.addArrangedSubview(makeSection(title: "Share your setup", rows: [NSStackView(views: [importButton, exportButton])]))
        stack.addArrangedSubview(makeSection(title: "Diagnostics", rows: [
            formRow("AeroSpace", aerospaceStatus),
            formRow("Tailscale", tailscaleStatus),
            formRow("Media players", mediaStatus),
            formRow("Weather", weatherStatus),
            formRow("Config file", configPathStatus)
        ]))

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

    private func configureAppearanceControls() {
        modePopup.addItems(withTitles: ["Follow System", "Light", "Dark"])
        modePopup.target = self
        modePopup.action = #selector(modeChanged)
        coveBorderButton.target = self
        coveBorderButton.action = #selector(visualChanged)
        densityPopup.addItems(withTitles: BarDensity.allCases.map(\.menuTitle))
        densityPopup.target = self
        densityPopup.action = #selector(visualChanged)
        workspaceAppsButton.target = self
        workspaceAppsButton.action = #selector(visualChanged)
    }

    private func configureWidgetOptionControls() {
        datePopup.addItems(withTitles: DateTimePresentation.allCases.map(\.menuTitle))
        datePopup.target = self
        datePopup.action = #selector(widgetOptionChanged)
        weatherUnitPopup.addItems(withTitles: WeatherUnit.allCases.map(\.menuTitle))
        weatherUnitPopup.target = self
        weatherUnitPopup.action = #selector(widgetOptionChanged)
        for button in [artistButton, hideIdlePlayerButton, weatherLocationButton] {
            button.target = self
            button.action = #selector(widgetOptionChanged)
        }
        for field in [weatherLocationField, latitudeField, longitudeField] {
            field.delegate = self
            field.controlSize = .small
        }
    }

    private func configureApplicationControls() {
        launchAtLoginButton.target = self
        launchAtLoginButton.action = #selector(launchAtLoginChanged)
        displayPopup.addItems(withTitles: BarDisplayMode.allCases.map(\.menuTitle))
        displayPopup.target = self
        displayPopup.action = #selector(applicationOptionChanged)
        refreshPopup.addItems(withTitles: ["1 second", "2 seconds", "5 seconds", "10 seconds"])
        refreshPopup.target = self
        refreshPopup.action = #selector(applicationOptionChanged)
        for label in [aerospaceStatus, tailscaleStatus, mediaStatus, weatherStatus, configPathStatus] {
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingMiddle
        }
    }

    func syncLaunchAtLogin() {
        launchAtLoginButton.allowsMixedState = true
        launchAtLoginButton.state = LaunchAtLogin.controlState
        launchAtLoginButton.isEnabled = LaunchAtLogin.isRunningFromAppBundle
        launchAtLoginButton.toolTip = LaunchAtLogin.statusDescription
    }

    @objc private func updateDiagnostics() {
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

    private func widgetRows() -> [[NSView]] {
        let kinds = WidgetKind.selectableCases
        var rows: [[NSView]] = []
        for start in stride(from: 0, to: kinds.count, by: 3) {
            var row: [NSView] = []
            for offset in 0..<3 {
                let index = start + offset
                if index < kinds.count {
                    let kind = kinds[index]
                    let button = NSButton(checkboxWithTitle: kind.menuTitle, target: self, action: #selector(widgetVisibilityChanged(_:)))
                    button.identifier = NSUserInterfaceItemIdentifier(kind.rawValue)
                    widgetButtons[kind] = button
                    row.append(button)
                } else {
                    row.append(NSView())
                }
            }
            rows.append(row)
        }
        return rows
    }

    private func makeSection(title: String, rows: [NSView]) -> NSView {
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
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 560),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
        ])
        let index: Int
        switch title {
        case "Composition", "Module order": index = 0
        case "Visible Widgets", "Widget Options": index = 1
        case "Appearance Studio": index = 2
        case "Connections", "Diagnostics", "Widget Providers": index = 3
        default: index = 4
        }
        sections[index, default: []].append(container)
        return container
    }

    private func formRow(_ title: String, _ control: NSView) -> NSView {
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

    private func coordinateRow() -> NSView {
        let fields = NSStackView()
        fields.orientation = .horizontal
        fields.spacing = 8
        latitudeField.placeholderString = "Latitude"
        longitudeField.placeholderString = "Longitude"
        latitudeField.widthAnchor.constraint(equalToConstant: 108).isActive = true
        longitudeField.widthAnchor.constraint(equalToConstant: 108).isActive = true
        fields.addArrangedSubview(latitudeField)
        fields.addArrangedSubview(longitudeField)
        return formRow("Coordinates", fields)
    }

    @objc private func modeChanged() {
        config.themeMode = ["system", "light", "dark"][max(0, modePopup.indexOfSelectedItem)]
        commit()
        sync(config: config)
    }

    @objc private func visualChanged() {
        config.visualPreferences.coveScreenBorder = coveBorderButton.state == .on
        config.visualPreferences.showsWorkspaceAppIcons = workspaceAppsButton.state == .on
        config.visualPreferences.density = BarDensity.allCases[max(0, densityPopup.indexOfSelectedItem)]
        commit()
    }

    @objc private func appearanceChanged(_ sender: AppearanceChoiceButton) {
        config.appearance = sender.choice
        commit()
        sync(config: config)
    }

    @objc private func widgetVisibilityChanged(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let kind = WidgetKind(rawValue: raw) else { return }
        if sender.state == .on {
            if !config.rightWidgets.contains(kind) { config.rightWidgets.append(kind) }
        } else {
            config.rightWidgets.removeAll { $0 == kind }
        }
        commit()
    }

    @objc private func widgetOptionChanged() {
        if datePopup.indexOfSelectedItem >= 0 { config.widgetPreferences.dateTimePresentation = DateTimePresentation.allCases[datePopup.indexOfSelectedItem] }
        if weatherUnitPopup.indexOfSelectedItem >= 0 { config.weather.unit = WeatherUnit.allCases[weatherUnitPopup.indexOfSelectedItem] }
        config.widgetPreferences.nowPlayingShowsArtist = artistButton.state == .on
        config.widgetPreferences.nowPlayingHidesWhenIdle = hideIdlePlayerButton.state == .on
        config.widgetPreferences.weatherShowsLocation = weatherLocationButton.state == .on
        commit()
    }

    @objc private func applicationOptionChanged() {
        config.hideInFullscreen = fullscreenButton.state == .on
        config.workspacesOnCurrentDisplay = localSpacesButton.state == .on
        if displayPopup.indexOfSelectedItem >= 0 { config.displayMode = BarDisplayMode.allCases[displayPopup.indexOfSelectedItem] }
        let refreshValues: [Double] = [1, 2, 5, 10]
        if refreshPopup.indexOfSelectedItem >= 0 { config.systemUpdateInterval = refreshValues[refreshPopup.indexOfSelectedItem] }
        commit()
    }

    @objc private func launchAtLoginChanged() {
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

    @objc private func applicationDidBecomeActive() {
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

    @objc private func undoLastChange() {
        guard let previous = undoStack.popLast() else { return }
        config = previous
        lastCommittedConfig = previous
        sync(config: previous)
        onChange(previous)
    }

    @objc private func resetAppearance() {
        config.visualPreferences = VisualPreferences(showsWorkspaceAppIcons: config.visualPreferences.showsWorkspaceAppIcons)
        config.appearance = .nativeGlass
        config.themeMode = "system"
        commit()
        sync(config: config)
    }

    private func commit() {
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

    @objc private func selectModule() {
        let selected = WidgetKind.selectableCases[max(0, modulePopup.indexOfSelectedItem)]
        for (kinds, row) in moduleRows { row.isHidden = !kinds.contains(selected) }
        noModuleOptions.isHidden = moduleRows.contains { $0.0.contains(selected) }
    }
    @objc private func sectionChanged() {
        for (index, views) in sections { views.forEach { $0.isHidden = index != sectionsControl.selectedSegment } }
    }
    @objc private func layoutChanged() {
        config.layout = BarLayout.allCases[max(0, layoutPopup.indexOfSelectedItem)]
        config.widgetPlacement = WidgetPlacement.allCases[max(0, placementPopup.indexOfSelectedItem)]
        commit()
        sync(config: config)
    }
    @objc private func providerChanged(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        config.providerPreferences.disabled.removeAll { $0 == id }
        if sender.state == .off { config.providerPreferences.disabled.append(id) }
        commit()
    }
    @objc private func connectionChanged() {
        config.integration = IntegrationMode.allCases[max(0, integrationPopup.indexOfSelectedItem)]
        commit()
    }
    @objc private func displayChanged() {
        for (id, enabled, popup) in displayControls {
            var override = config.displayOverrides[id] ?? DisplayOverride()
            override.enabled = enabled.state == .on
            override.layout = popup.indexOfSelectedItem > 0 ? BarLayout.allCases[popup.indexOfSelectedItem - 1] : nil
            config.displayOverrides[id] = override
        }
        commit()
    }
    private func rebuildWidgetOrder() {
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
    @objc private func moveModule(_ sender: NSButton) {
        let index = sender.tag / 2, destination = sender.tag / 2 + (sender.tag % 2 == 0 ? -1 : 1)
        guard config.rightWidgets.indices.contains(destination) else { return }
        config.rightWidgets.swapAt(index, destination)
        commit()
    }
    @objc private func importConfiguration() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { config = try BarConfig.decode(Data(contentsOf: url)); commit(); sync(config: config) }
        catch { ConfigurationStore.report(error.localizedDescription) }
    }
    @objc private func exportConfiguration() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "constellation-config.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        ConfigurationStore.save(config, to: url)
    }
}
