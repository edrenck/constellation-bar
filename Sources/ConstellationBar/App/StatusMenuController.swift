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

        menu.addItem(actionItem("Widgets…", action: #selector(openWidgetSettings)))
        menu.addItem(actionItem("Appearance…", action: #selector(openAppearanceSettings)))

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

    @objc private func openWidgetSettings() { showConfiguration(); configurationWindow.selectSection(1) }
    @objc private func openAppearanceSettings() { showConfiguration(); configurationWindow.selectSection(2) }

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
