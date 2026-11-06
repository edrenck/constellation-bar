import AppKit

enum WorkspaceQuery: Hashable { case focusedWorkspace, windows, focusedWindow }

struct WorkspaceSnapshot {
    var workspaces: [WorkspaceState] = []
    var focusedWindow: WindowIdentity?
    var status: String = "Standalone"
    /// A partial query still has useful workspace state; only unavailable sources need fallback.
    var isAvailable = true
    var unavailableQueries: Set<WorkspaceQuery> = []

    func retainingUnavailableFields(from previous: WorkspaceSnapshot) -> WorkspaceSnapshot {
        var value = self
        if unavailableQueries.contains(.focusedWorkspace) {
            let focused = previous.workspaces.first(where: \.isFocused)?.name
            for index in value.workspaces.indices { value.workspaces[index].isFocused = value.workspaces[index].name == focused }
        }
        if unavailableQueries.contains(.windows) {
            let oldWindows = Dictionary(previous.workspaces.map { ($0.name, $0.windows) }, uniquingKeysWith: { first, _ in first })
            for index in value.workspaces.indices { value.workspaces[index].windows = oldWindows[value.workspaces[index].name] ?? [] }
        }
        if unavailableQueries.contains(.focusedWindow),
           let old = previous.focusedWindow, value.workspaces.contains(where: { $0.name == old.workspace }) {
            value.focusedWindow = old
        }
        return value
    }
}
protocol WorkspaceProviding {
    func snapshot(config: BarConfig) -> WorkspaceSnapshot
    func switchToWorkspace(_ name: String) throws
    func focusWindow(_ id: Int) throws
}

struct WorkspaceCommandError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class AeroSpaceClient: WorkspaceProviding {
    private let binaryPath: String
    private let runner: CommandRunning
    init(binaryPath: String, runner: CommandRunning = CommandRunner()) {
        self.binaryPath = binaryPath
        self.runner = runner
    }
    private let windowFormat = "%{window-id}\t%{workspace}\t%{app-name}\t%{app-bundle-id}\t%{window-title}"

    func focusedWorkspace() -> String? {
        guard let path = ExecutableDiscovery.find("aerospace", override: binaryPath) else { return nil }
        let result = runner.run(path, ["list-workspaces", "--focused"], timeout: 1)
        let name = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.succeeded && !name.isEmpty ? name : nil
    }

    func snapshot(config: BarConfig) -> WorkspaceSnapshot {
        guard let path = ExecutableDiscovery.find("aerospace", override: binaryPath) else {
            return WorkspaceSnapshot(status: "AeroSpace not found", isAvailable: false)
        }
        let result = runner.run(path, ["list-workspaces", "--all", "--format", "%{workspace}\t%{monitor-appkit-nsscreen-screens-id}"], timeout: 1)
        guard result.succeeded else {
            return WorkspaceSnapshot(status: "AeroSpace unavailable · \(failure(result, operation: "Workspace list"))", isAvailable: false)
        }
        var issues: [String] = []
        var unavailable: Set<WorkspaceQuery> = []
        func query(_ args: [String], kind: WorkspaceQuery, operation: String, allowsNoFocusedWindow: Bool = false) -> String? {
            let result = runner.run(path, args, timeout: 1)
            if result.succeeded { return result.output }
            // The CLI explicitly reports this expected empty-workspace state as exit 1.
            if allowsNoFocusedWindow, result.status == 1, !result.timedOut, !result.outputTruncated,
               result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               result.error.trimmingCharacters(in: .whitespacesAndNewlines) == "No window is focused" { return "" }
            issues.append(failure(result, operation: operation))
            unavailable.insert(kind)
            return nil
        }
        let focused = query(["list-workspaces", "--focused"], kind: .focusedWorkspace, operation: "Focused workspace")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let windowOutput = query(["list-windows", "--all", "--format", windowFormat], kind: .windows, operation: "Window list")
        var windows: [WindowIdentity] = []
        if let windowOutput {
            let lines = windowOutput.split(whereSeparator: \.isNewline)
            windows = lines.compactMap { Self.parseWindow(String($0)) }
            if windows.count != lines.count { windows = []; issues.append("Window list returned invalid data"); unavailable.insert(.windows) }
        }
        let active = query(["list-windows", "--focused", "--format", windowFormat], kind: .focusedWindow, operation: "Focused window", allowsNoFocusedWindow: true)
        let focusedWindow = active.flatMap(Self.parseWindow)
        if let active, !active.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, focusedWindow == nil {
            issues.append("Focused window returned invalid data")
            unavailable.insert(.focusedWindow)
        }
        let discovered = Self.parseWorkspaces(result.output)
        if let focused, focused.isEmpty || !discovered.contains(where: { $0.name == focused }) {
            issues.append("Focused workspace returned invalid data")
            unavailable.insert(.focusedWorkspace)
        }
        let names = Self.orderedNames(discovered.map(\.name), preferred: config.workspaceNames)
        let byName = Dictionary(discovered.map { ($0.name, $0.monitor) }, uniquingKeysWith: { first, _ in first })
        return WorkspaceSnapshot(workspaces: names.map { name in
            WorkspaceState(name: name, isFocused: name == focused, windows: windows.filter { $0.workspace == name }, monitorIndex: byName[name] ?? nil, displayName: config.workspaceAliases[name])
        }, focusedWindow: focusedWindow, status: issues.isEmpty ? "AeroSpace connected" : "AeroSpace needs attention · " + issues.joined(separator: "; "), unavailableQueries: unavailable)
    }

    static func orderedNames(_ discovered: [String], preferred: [String]) -> [String] {
        var seen = Set<String>()
        let known = Set(discovered)
        return (preferred.filter { known.contains($0) } + discovered.sorted { $0.localizedStandardCompare($1) == .orderedAscending }).filter { seen.insert($0).inserted }
    }
    static func parseWorkspaces(_ output: String) -> [(name: String, monitor: Int?)] {
        output.split(whereSeparator: \.isNewline).compactMap {
            let parts = $0.split(separator: "\t", omittingEmptySubsequences: false)
            guard let name = parts.first, !name.isEmpty else { return nil }
            return (String(name), parts.count > 1 ? Int(parts[1]) : nil)
        }
    }
    static func parseWindow(_ line: String) -> WindowIdentity? {
        let parts = line.trimmingCharacters(in: .newlines).split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 5, let id = Int(parts[0]) else { return nil }
        return WindowIdentity(id: id, workspace: parts[1], appName: parts[2], bundleID: parts[3].isEmpty ? nil : parts[3], title: parts[4])
    }
    func switchToWorkspace(_ name: String) throws { try run(["workspace", name], operation: "Switch workspace") }
    func focusWindow(_ id: Int) throws { try run(["focus", "--window-id", String(id)], operation: "Focus window") }
    private func run(_ args: [String], operation: String) throws {
        guard let path = ExecutableDiscovery.find("aerospace", override: binaryPath) else {
            throw WorkspaceCommandError(message: "AeroSpace not found. Check the executable path in Workspaces settings.")
        }
        let result = runner.run(path, args, timeout: 2)
        guard result.succeeded else { throw WorkspaceCommandError(message: failure(result, operation: operation)) }
    }
    private func failure(_ result: CommandResult, operation: String) -> String {
        if result.timedOut { return "\(operation) timed out. Try again." }
        if result.outputTruncated { return "\(operation) returned incomplete output. Try again." }
        let detail = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(operation) failed" + (detail.isEmpty ? " (exit \(result.status))." : ": \(detail.prefix(120))")
    }
}

final class StandaloneWorkspaceProvider: WorkspaceProviding {
    func snapshot(config: BarConfig) -> WorkspaceSnapshot {
        var focused: WindowIdentity?
        DispatchQueue.main.sync {
            if let app = NSWorkspace.shared.frontmostApplication {
                focused = WindowIdentity(id: Int(app.processIdentifier), workspace: "", appName: app.localizedName ?? "Application", bundleID: app.bundleIdentifier, title: "")
            }
        }
        return WorkspaceSnapshot(focusedWindow: focused)
    }
    func switchToWorkspace(_ name: String) {}
    func focusWindow(_ id: Int) { NSRunningApplication(processIdentifier: pid_t(id))?.activate(options: []) }
}
