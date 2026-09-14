import Foundation

extension BarConfig {
    /// Providers must run even when their only presentation is on another display or in the center.
    var widgetsForSampling: [WidgetKind] {
        var result = WidgetKind.consolidated(widgetLayout.allWidgetKinds + rightWidgets + centerWidgets)
        for override in displayOverrides.values where override.enabled != false {
            let layoutKinds = override.widgetLayout?.allWidgetKinds ?? []
            for kind in layoutKinds + (override.widgets ?? []) + (override.centerWidgets ?? []) where !result.contains(kind) {
                result.append(kind)
            }
        }
        return result
    }

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
        return DisplayOverride(enabled: displayOverrides[id]?.enabled ?? true,
            layout: local.layout, hideInFullscreen: local.hideInFullscreen,
            workspaceVisibility: displayOverrides[id]?.workspaceVisibility ?? (workspacesOnCurrentDisplay ? .local : .all),
            selectedWorkspaces: displayOverrides[id]?.selectedWorkspaces,
            appearance: local.appearance, themeMode: local.themeMode,
            barPresentation: local.barPresentation, widgetLayout: local.widgetLayout, visualPreferences: local.visualPreferences)
    }
}
