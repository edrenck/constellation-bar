import AppKit

struct WorkspaceSnapshot {
    var workspaces: [WorkspaceState] = []
    var focusedWindow: WindowIdentity?
    var status: String = "Standalone"
}
protocol WorkspaceProviding {
    func snapshot(config: BarConfig) -> WorkspaceSnapshot
    func switchToWorkspace(_ name: String)
    func focusWindow(_ id: Int)
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
            return WorkspaceSnapshot(status: "AeroSpace not found")
        }
        let result = runner.run(path, ["list-workspaces", "--all", "--format", "%{workspace}\t%{monitor-appkit-nsscreen-screens-id}"], timeout: 1)
        guard result.succeeded else {
            return WorkspaceSnapshot(status: result.timedOut ? "AeroSpace timed out" : "AeroSpace unavailable · \(result.error.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))")
        }
        let focused = runner.run(path, ["list-workspaces", "--focused"], timeout: 1).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let windows = runner.run(path, ["list-windows", "--all", "--format", windowFormat], timeout: 1).output.split(whereSeparator: \.isNewline).compactMap { Self.parseWindow(String($0)) }
        let active = runner.run(path, ["list-windows", "--focused", "--format", windowFormat], timeout: 1).output
        let discovered = Self.parseWorkspaces(result.output)
        let names = Self.orderedNames(discovered.map(\.name), preferred: config.workspaceNames)
        let byName = Dictionary(discovered.map { ($0.name, $0.monitor) }, uniquingKeysWith: { first, _ in first })
        return WorkspaceSnapshot(workspaces: names.map { name in
            WorkspaceState(name: name, isFocused: name == focused, windows: windows.filter { $0.workspace == name }, monitorIndex: byName[name] ?? nil, displayName: config.workspaceAliases[name])
        }, focusedWindow: Self.parseWindow(active), status: "AeroSpace connected")
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
    func switchToWorkspace(_ name: String) { run(["workspace", name]) }
    func focusWindow(_ id: Int) { run(["focus", "--window-id", String(id)]) }
    private func run(_ args: [String]) {
        guard let path = ExecutableDiscovery.find("aerospace", override: binaryPath) else { return }
        _ = runner.run(path, args, timeout: 2)
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
