import Foundation
import AppKit


struct BarState: Equatable {
    var workspaces: [WorkspaceState]
    var focusedWindow: WindowIdentity?
    var system: SystemState
    var providerStatus: String = ""

    var allWindows: [WindowIdentity] { workspaces.flatMap(\.windows) }
}

protocol BarInteractionDelegate: AnyObject {
    func switchToWorkspace(_ name: String)
    func focusWindow(_ id: Int, workspace: String)
    func reorderWidgets(_ kinds: [WidgetKind], displayID: String?, centered: Bool)
    func performWidgetAction(_ action: WidgetAction, completion: @escaping (String?) -> Void)
}

enum PlaybackCommand {
    case previous
    case playPause
    case next
    case toggleShuffle
    case cycleRepeat
}
