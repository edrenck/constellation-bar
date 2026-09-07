import AppKit
import Foundation
import IOKit.ps
import ServiceManagement

final class StatusMenuController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var config: BarConfig
    private let onChange: (BarConfig) -> Void
    private lazy var configurationWindow = ConfigurationWindowController(config: config) { [weak self] updated in
        self?.replaceConfig(updated)
    }

    init(config: BarConfig, onChange: @escaping (BarConfig) -> Void) {
        self.config = config
        self.onChange = onChange
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "sparkles.rectangle.stack", accessibilityDescription: "ConstellationBar")
        statusItem.button?.image?.isTemplate = true
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActive), name: NSApplication.didBecomeActiveNotification, object: nil)
        rebuildMenu()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let heading = NSMenuItem(title: "ConstellationBar", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        menu.addItem(actionItem("About ConstellationBar…", action: #selector(showAbout)))
        menu.addItem(.separator())

        let customize = actionItem("Customize Bar…", action: #selector(openCustomizer))
        customize.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
        menu.addItem(customize)
        let launchAtLogin = actionItem("Launch at Login", action: #selector(toggleLaunchAtLogin))
        launchAtLogin.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        launchAtLogin.state = LaunchAtLogin.controlState
        launchAtLogin.isEnabled = LaunchAtLogin.isRunningFromAppBundle
        launchAtLogin.toolTip = LaunchAtLogin.statusDescription
        menu.addItem(launchAtLogin)
        menu.addItem(.separator())

        let appearance = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        let appearanceMenu = NSMenu()
        for choice in BarAppearance.allCases {
            appearanceMenu.addItem(actionItem(choice.title, action: #selector(selectAppearance(_:)), representedObject: choice, state: config.appearance == choice))
        }
        appearanceMenu.addItem(.separator())
        for (title, mode, action) in [("Follow System", "system", #selector(useSystemTheme)), ("Light", "light", #selector(useLightTheme)), ("Dark", "dark", #selector(useDarkTheme))] {
            let item = actionItem(title, action: action, state: config.themeMode == mode)
            item.isEnabled = config.appearance.isNative
            appearanceMenu.addItem(item)
        }
        appearance.submenu = appearanceMenu
        menu.addItem(appearance)

        let widgets = NSMenuItem(title: "Widgets", action: nil, keyEquivalent: "")
        let widgetsMenu = NSMenu()
        for kind in WidgetKind.selectableCases {
            let item = actionItem(kind.menuTitle, action: #selector(toggleWidget(_:)), representedObject: kind, state: config.rightWidgets.contains(kind))
            item.image = NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: nil)
            widgetsMenu.addItem(item)
        }
        widgetsMenu.addItem(.separator())
        let presets = NSMenuItem(title: "Presets", action: nil, keyEquivalent: "")
        let presetsMenu = NSMenu()
        presetsMenu.addItem(actionItem("Essentials", action: #selector(essentialsWidgetPreset)))
        presetsMenu.addItem(actionItem("Minimal", action: #selector(minimalWidgetPreset)))
        presetsMenu.addItem(actionItem("Daily", action: #selector(dailyWidgetPreset)))
        presetsMenu.addItem(actionItem("Performance", action: #selector(performanceWidgetPreset)))
        presets.submenu = presetsMenu
        widgetsMenu.addItem(presets)
        widgets.submenu = widgetsMenu
        menu.addItem(widgets)

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Configuration", action: nil, keyEquivalent: "")
        let settingsMenu = NSMenu()
        settingsMenu.addItem(actionItem("Open Config File", action: #selector(openConfigFile)))
        settingsMenu.addItem(actionItem("Reload from Disk", action: #selector(reloadConfig)))
        settings.submenu = settingsMenu
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(actionItem("Quit ConstellationBar", action: #selector(quit)))
        statusItem.menu = menu
    }

    func sync(config: BarConfig) {
        self.config = config
        configurationWindow.sync(config: config)
        rebuildMenu()
    }

    func showConfiguration() {
        configurationWindow.present(config: config)
    }

    private func actionItem(_ title: String, action: Selector, representedObject: Any? = nil, state: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = representedObject
        item.state = state ? .on : .off
        return item
    }

    private func apply(_ update: (inout BarConfig) -> Void) {
        update(&config)
        persistConfig()
        onChange(config)
        rebuildMenu()
    }

    private func replaceConfig(_ updated: BarConfig) {
        config = updated
        persistConfig()
        onChange(config)
        rebuildMenu()
    }

    @objc private func openCustomizer() {
        showConfiguration()
    }

    @objc private func applicationDidBecomeActive() {
        rebuildMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        if LaunchAtLogin.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            return
        }
        do {
            try LaunchAtLogin.setEnabled(!LaunchAtLogin.isRegistered)
        } catch {
            presentLaunchAtLoginError(error)
        }
        rebuildMenu()
        configurationWindow.syncLaunchAtLogin()
    }

    private func presentLaunchAtLoginError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn’t Change Launch at Login"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    @objc private func useSystemTheme() { apply { $0.themeMode = "system" } }
    @objc private func useDarkTheme() { apply { $0.themeMode = "dark" } }
    @objc private func useLightTheme() { apply { $0.themeMode = "light" } }
    @objc private func selectAppearance(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? BarAppearance else { return }
        apply { $0.appearance = choice }
    }
    @objc private func essentialsWidgetPreset() { apply { $0.rightWidgets = [.battery, .vpn, .network, .dateTime, .system] } }
    @objc private func minimalWidgetPreset() { apply { $0.rightWidgets = [.vpn, .network, .dateTime] } }
    @objc private func dailyWidgetPreset() { apply { $0.rightWidgets = [.weather, .nowPlaying, .dateTime, .battery] } }
    @objc private func performanceWidgetPreset() { apply { $0.rightWidgets = [.network, .system, .thermal, .disk] } }

    @objc private func toggleWidget(_ sender: NSMenuItem) {
        guard let kind = sender.representedObject as? WidgetKind else { return }
        apply { config in
            if config.rightWidgets.contains(kind) {
                config.rightWidgets.removeAll { $0 == kind }
            } else {
                config.rightWidgets.append(kind)
            }
        }
    }

    @objc private func openConfigFile() {
        let url = ConfigFile.prepareWritableURL()
        if !FileManager.default.fileExists(atPath: url.path) {
            guard ConfigurationStore.save(config, to: url) else { return }
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func reloadConfig() {
        let loaded = BarConfig.load()
        if let error = ConfigurationStore.lastError { ConfigurationStore.report(error); return }
        config = loaded
        configurationWindow.sync(config: config)
        onChange(config)
        rebuildMenu()
    }

    @objc private func showAbout() {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "local"
        let commit = bundle.object(forInfoDictionaryKey: "ConstellationSourceCommit") as? String ?? "unknown"
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "ConstellationBar",
            .applicationVersion: version,
            .version: "\(build) · \(commit)",
            .credits: NSAttributedString(string: "Native macOS workspace and status bar")
        ])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func persistConfig() {
        ConfigurationStore.save(config)
    }
}
