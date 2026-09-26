import AppKit
import Foundation
import IOKit.ps
import ServiceManagement

enum LaunchAtLogin {
    private static let desiredKey = "ConstellationLaunchAtLoginRequested"
    private static let registeredPathKey = "ConstellationLoginRegisteredPath"
    private(set) static var lastError: String?

    static var status: SMAppService.Status { SMAppService.mainApp.status }
    static var isEnabled: Bool { status == .enabled }
    static var isRegistered: Bool { status == .enabled || status == .requiresApproval }
    static var controlState: NSControl.StateValue {
        switch status {
        case .enabled: return .on
        case .requiresApproval: return .mixed
        default: return .off
        }
    }
    static var isRunningFromAppBundle: Bool { Bundle.main.bundleURL.pathExtension.lowercased() == "app" }
    static var statusDescription: String {
        guard isRunningFromAppBundle else { return "Available in the installed ConstellationBar.app." }
        if let lastError { return lastError }
        switch status {
        case .enabled: return "Enabled — ConstellationBar will open at your next login."
        case .requiresApproval: return "Approval required. Enable ConstellationBar in System Settings → General → Login Items."
        case .notRegistered: return "Disabled. Enable startup to open the bar at login."
        case .notFound: return "Registration is unavailable. Move the app to Applications and repair startup."
        @unknown default: return "macOS returned an unknown login-item status."
        }
    }

    /// Re-register a requested login item when a moved or replaced app invalidates it.
    /// Do not prompt at ordinary startup; the settings action handles consent.
    static func reconcileAtStartup() {
        guard isRunningFromAppBundle else { return }
        let defaults = UserDefaults.standard
        if defaults.object(forKey: desiredKey) == nil {
            if isRegistered { defaults.set(true, forKey: desiredKey) }
            defaults.set(Bundle.main.bundleURL.path, forKey: registeredPathKey)
            return
        }
        guard shouldReconcile(requested: defaults.bool(forKey: desiredKey), status: status,
                              registeredPath: defaults.string(forKey: registeredPathKey), currentPath: Bundle.main.bundleURL.path) else { return }
        let moved = defaults.string(forKey: registeredPathKey) != Bundle.main.bundleURL.path
        do {
            try register(repair: moved || status == .notFound, requestApproval: false)
            defaults.set(Bundle.main.bundleURL.path, forKey: registeredPathKey)
        }
        catch { lastError = error.localizedDescription }
    }

    static func shouldReconcile(requested: Bool, status: SMAppService.Status, registeredPath: String?, currentPath: String) -> Bool {
        requested && status != .requiresApproval && (registeredPath != currentPath || status == .notRegistered || status == .notFound)
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard isRunningFromAppBundle else { throw LaunchAtLoginError.requiresAppBundle }
        lastError = nil
        do {
            if enabled { try register(repair: status == .notFound, requestApproval: true) }
            else if status != .notRegistered { try SMAppService.mainApp.unregister() }
            UserDefaults.standard.set(enabled, forKey: desiredKey)
            UserDefaults.standard.set(Bundle.main.bundleURL.path, forKey: registeredPathKey)
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    static func openSettings() { SMAppService.openSystemSettingsLoginItems() }

    static func repairRegistration() throws {
        guard isRunningFromAppBundle else { throw LaunchAtLoginError.requiresAppBundle }
        lastError = nil
        do {
            try register(repair: true, requestApproval: true)
            UserDefaults.standard.set(true, forKey: desiredKey)
            UserDefaults.standard.set(Bundle.main.bundleURL.path, forKey: registeredPathKey)
        } catch { lastError = error.localizedDescription; throw error }
    }

    private static func register(repair: Bool, requestApproval: Bool) throws {
        if repair, isRegistered { try SMAppService.mainApp.unregister() }
        if status != .enabled && status != .requiresApproval { try SMAppService.mainApp.register() }
        if status == .requiresApproval {
            if requestApproval { SMAppService.openSystemSettingsLoginItems() }
        } else if status != .enabled { throw LaunchAtLoginError.registrationFailed }
    }
}

enum LaunchAtLoginError: LocalizedError {
    case requiresAppBundle
    case registrationFailed
    var errorDescription: String? {
        switch self {
        case .requiresAppBundle: return "Launch at login is available in the built ConstellationBar.app, not when using swift run."
        case .registrationFailed: return "macOS did not enable the login item. Move ConstellationBar to Applications, then use Repair Startup."
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: BarController?
    private var statusController: StatusMenuController?
    private let startupSmokeTest = CommandLine.arguments.contains("--startup-smoke-test")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if !startupSmokeTest, let bundleID = Bundle.main.bundleIdentifier,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter({ $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated &&
                $0.processIdentifier != UpdateTransaction.installerPIDForStartup(arguments: CommandLine.arguments) })
            .min(by: { $0.processIdentifier < $1.processIdentifier }),
           existing.processIdentifier < ProcessInfo.processInfo.processIdentifier {
            existing.activate(options: [])
            DistributedNotificationCenter.default().postNotificationName(Self.reopenNotification, object: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(openSettings), name: Self.reopenNotification, object: nil)
        var loaded = startupSmokeTest ? BarConfig.default : BarConfig.load()
        if startupSmokeTest {
            loaded.integration = .standalone
            loaded.displayMode = .primaryOnly
            // The smoke fixture must remain visible even if the developer's
            // foreground app currently covers the display or is fullscreen.
            loaded.hideInFullscreen = false
        }
        controller = BarController(config: loaded)
        statusController = StatusMenuController(config: loaded) { [weak self] config in
            self?.controller?.apply(config: config)
        }
        controller?.onConfigChange = { [weak self] config in
            self?.statusController?.sync(config: config)
        }
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "ConstellationBar")
        let settings = NSMenuItem(title: "Customize Bar…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit ConstellationBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
        controller?.start()
        if startupSmokeTest {
            // Run the normal startup graph and event loop, then verify the real
            // windows. Fixture config avoids reading or changing personal settings.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.statusController?.showConfiguration()
                let bars = NSApp.windows.compactMap { $0 as? BarWindow }.filter(\.isVisible)
                let settings = NSApp.windows.first { $0.title == "Customize ConstellationBar" && $0.isVisible }
                guard !bars.isEmpty, let settings, settings.contentView != nil else {
                    let windows = NSApp.windows.map { "\(type(of: $0)): title=\($0.title), visible=\($0.isVisible), frame=\($0.frame)" }.joined(separator: "; ")
                    fputs("STARTUP_UI_FAILED: bar or customization window missing; delegate=\(self != nil), controller=\(self?.controller != nil), screens=\(NSScreen.screens.count), windows=[\(windows)]\n", stderr)
                    exit(1)
                }
                print("STARTUP_UI_OK")
                NSApp.terminate(nil)
            }
            return
        }
        // Acknowledge only after the normal startup graph has initialized and the
        // main run loop gets a turn. The helper rolls back crashes before this point.
        DispatchQueue.main.async {
            UpdateTransaction.acknowledgeStartup(arguments: CommandLine.arguments)
        }
        LaunchAtLogin.reconcileAtStartup()
        AppUpdater.shared.startAutomaticCheck()
        if let error = ConfigurationStore.lastError { ConfigurationStore.report(error) }
        if CommandLine.arguments.contains("--configure") || ConfigurationStore.activeURL == nil {
            DispatchQueue.main.async { [weak self] in self?.statusController?.showConfiguration() }
        }
    }

    private static let reopenNotification = Notification.Name("dev.constellation.bar.reopen")

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusController?.showConfiguration()
        return true
    }

    @objc private func openSettings() { statusController?.showConfiguration() }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
        controller?.stop()
    }
}
