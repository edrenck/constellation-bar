import Foundation

/// The same effective displays own both rendered bars and the providers they need.
/// Connected IDs are ordered with the primary display first; saved overrides are not connections.
struct DisplayScope: Equatable {
    let displayIDs: [String]
    let widgets: [WidgetKind]

    init(config: BarConfig, connectedDisplayIDs: [String]) {
        let candidates = config.displayMode == .primaryOnly ? Array(connectedDisplayIDs.prefix(1)) : connectedDisplayIDs
        var seen = Set<String>()
        displayIDs = candidates.filter { seen.insert($0).inserted && config.displayOverrides[$0]?.enabled != false }
        widgets = WidgetKind.consolidated(displayIDs.flatMap { config.forDisplay($0).widgetLayout.allWidgetKinds })
    }
}

extension BarConfig {
    func stateForDisplay(_ state: BarState, id: String, monitorIndex: Int) -> BarState {
        let override = displayOverrides[id]
        let visibility = override?.workspaceVisibility ?? (workspacesOnCurrentDisplay ? .local : .all)
        var result = state
        switch visibility {
        case .local:
            result.workspaces = state.workspaces.filter { $0.monitorIndex == nil || $0.monitorIndex == monitorIndex }
        case .all: break
        case .hidden: result.workspaces = []
        case .selected:
            let names = override?.selectedWorkspaces ?? []
            result.workspaces = names.compactMap { name in state.workspaces.first { $0.name == name } }
        }
        // Hiding workspace buttons should not also hide the active application.
        if visibility != .hidden, let focused = result.focusedWindow, !focused.workspace.isEmpty,
           !result.workspaces.contains(where: { $0.name == focused.workspace }) { result.focusedWindow = nil }
        return result
    }
}

extension BarConfig {
    func resolvedOverride(for id: String) -> DisplayOverride {
        let local = forDisplay(id)
        return DisplayOverride(sizeMultiplier: local.sizeMultiplier, enabled: displayOverrides[id]?.enabled ?? true,
            layout: local.layout, hideInFullscreen: local.hideInFullscreen,
            workspaceVisibility: displayOverrides[id]?.workspaceVisibility ?? (workspacesOnCurrentDisplay ? .local : .all),
            selectedWorkspaces: displayOverrides[id]?.selectedWorkspaces,
            appearance: local.appearance, typesetScheme: local.typesetScheme, typesetVariant: local.typesetVariant, themeMode: local.themeMode,
            barPresentation: local.barPresentation, widgetLayout: local.widgetLayout, visualPreferences: local.visualPreferences)
    }
}
