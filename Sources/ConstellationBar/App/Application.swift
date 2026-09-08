import AppKit
import Foundation
import IOKit.ps
import ServiceManagement

enum LaunchAtLogin {
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static var isEnabled: Bool {
        status == .enabled
    }

    static var isRegistered: Bool {
        status == .enabled || status == .requiresApproval
    }

    static var controlState: NSControl.StateValue {
        switch status {
        case .enabled: return .on
        case .requiresApproval: return .mixed
        default: return .off
        }
    }

    static var isRunningFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app"
    }

    static var statusDescription: String {
        guard isRunningFromAppBundle else {
            return "Unavailable when run from the command line"
        }
        switch status {
        case .enabled:
            return "Enabled"
        case .requiresApproval:
            return "Needs approval in System Settings"
        case .notRegistered:
            return "Disabled"
        case .notFound:
            return "Unavailable for this app bundle"
        @unknown default:
            return "Unknown"
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard isRunningFromAppBundle else {
            throw LaunchAtLoginError.requiresAppBundle
        }
        if enabled {
            if status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if status != .notRegistered {
            try SMAppService.mainApp.unregister()
        }
    }
}

enum LaunchAtLoginError: LocalizedError {
    case requiresAppBundle

    var errorDescription: String? {
        switch self {
        case .requiresAppBundle:
            return "Launch at login is available in the built ConstellationBar.app, not when using swift run."
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: BarController?
    private var statusController: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let bundleID = Bundle.main.bundleIdentifier,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter({ $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated })
            .min(by: { $0.processIdentifier < $1.processIdentifier }),
           existing.processIdentifier < ProcessInfo.processInfo.processIdentifier {
            existing.activate(options: [])
            DistributedNotificationCenter.default().postNotificationName(Self.reopenNotification, object: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(openSettings), name: Self.reopenNotification, object: nil)
        let loaded = BarConfig.load()
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
