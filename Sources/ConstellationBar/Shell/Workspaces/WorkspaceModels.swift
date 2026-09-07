import Foundation
import AppKit


struct WorkspaceState: Equatable {
    var name: String
    var isFocused: Bool
    var windows: [WindowIdentity]
    var monitorIndex: Int? = nil
    var displayName: String? = nil

    var apps: [AppIdentity] {
        var seen = Set<AppIdentity>()
        return windows.compactMap { window in
            let app = AppIdentity(name: window.appName, bundleID: window.bundleID)
            return seen.insert(app).inserted ? app : nil
        }
    }
}

struct AppIdentity: Equatable, Hashable {
    var name: String
    var bundleID: String?
}

struct WindowIdentity: Equatable, Hashable {
    var id: Int
    var workspace: String
    var appName: String
    var bundleID: String?
    var title: String

    var appIdentity: AppIdentity {
        AppIdentity(name: appName, bundleID: bundleID)
    }
}
