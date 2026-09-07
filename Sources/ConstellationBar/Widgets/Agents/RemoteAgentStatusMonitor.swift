import Foundation

struct CodexSSHHost: Decodable, Equatable {
    let hostId: String
    let displayName: String
    let hostname: String?
    let alias: String?
    let sshPort: Int?
    let identity: String?
    var destination: String { alias.flatMap { $0.isEmpty ? nil : $0 } ?? hostname ?? "" }
    var valid: Bool {
        hostId.hasPrefix("remote-ssh-codex-managed:") && !displayName.isEmpty && displayName.count <= 100
        && !destination.isEmpty && destination.count <= 255 && !destination.hasPrefix("-")
        && !destination.contains(where: { $0.isWhitespace || $0.isNewline || $0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) })
        && (sshPort == nil || (1...65535).contains(sshPort!))
    }
    static func discover() throws -> [CodexSSHHost] {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        let url = home.appendingPathComponent(".codex-global-state.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard let data = BoundedFile.read(url, maximumBytes: 4 * 1_048_576) else { throw DiscoveryError.unreadable }
        return try decode(data)
    }
    static func decode(_ data: Data) throws -> [CodexSSHHost] {
        struct Settings: Decodable {
            let hosts: [CodexSSHHost]?
            enum CodingKeys: String, CodingKey { case hosts = "codex-managed-remote-connections" }
        }
        let hosts = try JSONDecoder().decode(Settings.self, from: data).hosts ?? []
        guard hosts.count <= 16, hosts.allSatisfy(\.valid), Set(hosts.map(\.hostId)).count == hosts.count else { throw DiscoveryError.unreadable }
        return hosts
    }
    private enum DiscoveryError: Error { case unreadable }
}

/// Remote probes are cached and dispatched independently of native provider sampling.
/// At most two SSH processes run concurrently; failures back off and never reuse stale counts.
final class RemoteAgentStatusMonitor {
    private struct Entry {
        var host: CodexSSHHost
        var snapshot: AgentProviderSnapshot
        var nextPoll = Date.distantPast
        var failures = 0
        var inFlight = false
    }
    private let lock = NSLock()
    private let queue: OperationQueue = {
        let queue = OperationQueue(); queue.name = "dev.constellation.agent-ssh"
        queue.maxConcurrentOperationCount = 2; queue.qualityOfService = .utility
        return queue
    }()
    private let discover: () throws -> [CodexSSHHost]
    private let runner: CommandRunning
    private let now: () -> Date
    private var entries: [String: Entry] = [:]
    private var nextDiscovery = Date.distantPast
    private var discoveryFailed = false
    private var generation = 0
    init(discover: @escaping () throws -> [CodexSSHHost] = CodexSSHHost.discover,
         runner: CommandRunning = CommandRunner(), now: @escaping () -> Date = Date.init) {
        self.discover = discover; self.runner = runner; self.now = now
    }
    func snapshots(enabled: Bool) -> [AgentProviderSnapshot] {
        lock.lock(); defer { lock.unlock() }
        guard enabled else {
            generation += 1; entries = [:]; queue.cancelAllOperations(); nextDiscovery = .distantPast
            return []
        }
        let date = now()
        if date >= nextDiscovery {
            nextDiscovery = date.addingTimeInterval(15)
            do {
                let hosts = try discover()
                entries = entries.filter { id, entry in hosts.contains(where: { $0.hostId == id && $0 == entry.host }) }
                for host in hosts where entries[host.hostId] == nil {
                    entries[host.hostId] = Entry(host: host, snapshot: Self.unavailable(host, message: "Connecting over SSH…"))
                }
                discoveryFailed = false
            } catch { discoveryFailed = true }
        }
        for id in Array(entries.keys) {
            guard var entry = entries[id], !entry.inFlight, date >= entry.nextPoll else { continue }
            entry.inFlight = true; entries[id] = entry
            let host = entry.host, requestGeneration = generation
            queue.addOperation { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let current = self.generation == requestGeneration && self.entries[id]?.host == host
                self.lock.unlock()
                guard current else { return }
                let result = self.runner.run("/usr/bin/ssh", Self.arguments(for: host), timeout: 10)
                let sampled = self.now()
                let snapshot = Self.decode(result, host: host, at: sampled)
                self.lock.lock(); defer { self.lock.unlock() }
                guard self.generation == requestGeneration, var entry = self.entries[id], entry.host == host else { return }
                entry.snapshot = snapshot; entry.inFlight = false
                entry.failures = snapshot.available ? 0 : min(entry.failures + 1, 3)
                entry.nextPoll = sampled.addingTimeInterval(snapshot.available ? 10 : Double(15 * (1 << entry.failures)))
                self.entries[id] = entry
            }
        }
        var snapshots = entries.values.sorted { $0.host.hostId < $1.host.hostId }.map { entry -> AgentProviderSnapshot in
            if entry.snapshot.available, let sampled = entry.snapshot.sampledAt, date.timeIntervalSince(sampled) > 30 {
                return Self.unavailable(entry.host, message: "Status is stale; checking SSH connection…", at: sampled)
            }
            return entry.snapshot
        }
        if discoveryFailed {
            snapshots.append(AgentProviderSnapshot(id: "codex:ssh-discovery", name: "Codex", message: "Cannot read Codex's saved SSH connections", hostName: "SSH hosts"))
        }
        return snapshots
    }
    static func arguments(for host: CodexSSHHost) -> [String] {
        var args = ["-T", "-n", "-o", "PermitLocalCommand=no", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=3", "-o", "ServerAliveInterval=3", "-o", "ServerAliveCountMax=1", "-o", "ClearAllForwardings=yes", "-o", "ControlMaster=no", "-o", "ControlPath=none"]
        if let port = host.sshPort { args += ["-p", String(port)] }
        if let identity = host.identity, !identity.isEmpty { args += ["-i", NSString(string: identity).expandingTildeInPath] }
        let encoded = Data(RemoteAgentProbe.source.utf8).base64EncodedString()
        // OpenSSH joins remote command arguments into shell text. This command uses only fixed
        // syntax and a base64 alphabet; host/user/identity strings never enter that shell text.
        let command = "python3 -c \"import base64;exec(base64.b64decode('\(encoded)'))\""
        return args + ["--", host.destination, command]
    }
    private static func unavailable(_ host: CodexSSHHost, message: String, at date: Date? = nil) -> AgentProviderSnapshot {
        AgentProviderSnapshot(id: "codex:" + host.hostId, name: "Codex", message: message, sampledAt: date, hostName: host.displayName)
    }
    static func decode(_ result: CommandResult, host: CodexSSHHost, at date: Date) -> AgentProviderSnapshot {
        guard result.succeeded else {
            return unavailable(host, message: result.timedOut ? "SSH timed out · host may be offline" : "SSH unavailable · check connection, authentication and Python 3", at: date)
        }
        struct Payload: Decodable { let version: Int; let available: Bool; let tasks: [AgentTaskStatus]; let message: String }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: Data(result.output.utf8)),
              payload.version == 1, payload.tasks.count <= 256,
              Set(payload.tasks.map(\.id)).count == payload.tasks.count,
              payload.tasks.allSatisfy({ UUID(uuidString: $0.id) != nil && $0.title.count <= 240 && $0.project.count <= 240 && $0.statusDetail.count <= 240 }) else {
            return unavailable(host, message: "Remote status response is unsupported or invalid", at: date)
        }
        return AgentProviderSnapshot(id: "codex:" + host.hostId, name: "Codex", tasks: payload.available ? payload.tasks : [], available: payload.available,
            message: payload.available ? "Connected over SSH" : "Remote Codex data is missing, busy, or unsupported", sampledAt: date, hostName: host.displayName)
    }
}
