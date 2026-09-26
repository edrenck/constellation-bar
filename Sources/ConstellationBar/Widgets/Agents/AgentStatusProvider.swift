import Foundation
import SQLite3
import Darwin

/// Agent providers report tasks, not operating-system processes. New providers share the same UI.
protocol AgentStatusIntegrating: AnyObject {
    var id: String { get }
    func snapshot() -> AgentProviderSnapshot
}

enum AgentTaskActivity: String, Equatable, Codable { case active, idle, unknown }
struct AgentTaskStatus: Equatable, Codable {
    var id: String
    var activity: AgentTaskActivity
    var title: String = ""
    var project: String = ""
    var statusDetail: String = ""
    var displayTitle: String { title.isEmpty ? "Untitled task · " + String(id.prefix(8)) : title }
    var activityLabel: String {
        switch activity {
        case .active: return "Active"
        case .idle: return "Idle"
        case .unknown: return "Unknown"
        }
    }
    static func displayText(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace || $0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }).joined(separator: " ")
    }
}
struct AgentProviderSnapshot: Equatable {
    var id: String
    var name: String
    var tasks: [AgentTaskStatus] = []
    var available = false
    var message = "Not sampled yet"
    var sampledAt: Date? = nil
    var hostName: String = "This Mac"
    var sortedTasks: [AgentTaskStatus] {
        func rank(_ activity: AgentTaskActivity) -> Int {
            switch activity { case .active: return 0; case .unknown: return 1; case .idle: return 2 }
        }
        return tasks.sorted {
            if rank($0.activity) != rank($1.activity) { return rank($0.activity) < rank($1.activity) }
            if $0.displayTitle != $1.displayTitle { return $0.displayTitle < $1.displayTitle }
            return $0.id < $1.id
        }
    }
    var activeCount: Int { tasks.filter { $0.activity == .active }.count }
    var idleCount: Int { tasks.filter { $0.activity == .idle }.count }
    var unknownCount: Int { tasks.filter { $0.activity == .unknown }.count }
}
struct AgentStatusState: Equatable {
    var providers: [AgentProviderSnapshot] = []
    var activeCount: Int { providers.filter(\.available).reduce(0) { $0 + $1.activeCount } }
    var unknownCount: Int { providers.filter(\.available).reduce(0) { $0 + $1.unknownCount } }
    var readableProviderCount: Int { providers.filter(\.available).count }
    var hasReadableProvider: Bool { providers.contains(where: \.available) }
    var isComplete: Bool { !providers.isEmpty && providers.allSatisfy { $0.available && $0.unknownCount == 0 } }
    /// Saved SSH hosts can be offline by design. Keep their connectivity separate from
    /// readable task lifecycles so one sleeping computer does not obscure every count.
    var coverageDetail: String {
        guard !providers.isEmpty else { return "Monitoring disabled" }
        guard readableProviderCount < providers.count else { return "All configured hosts checked" }
        return "Counts from \(readableProviderCount) of \(providers.count) configured hosts"
    }
    var taskSummary: String {
        guard hasReadableProvider else { return "Status unavailable" }
        let active = "\(activeCount) active \(activeCount == 1 ? "task" : "tasks")"
        if unknownCount > 0 { return active + " · \(unknownCount) unknown" }
        if activeCount == 0 {
            return readableProviderCount < providers.count ? "No tasks running on checked hosts" : "No tasks running"
        }
        return active
    }
}
final class AgentStatusProvider: SystemProviding {
    let kinds: Set<WidgetKind> = [.agentStatus]
    private let integrations: [AgentStatusIntegrating]
    private let remote: RemoteAgentStatusMonitor?
    convenience init() { self.init(integrations: [CodexAgentStatusIntegration()], remote: RemoteAgentStatusMonitor()) }
    init(integrations: [AgentStatusIntegrating], remote: RemoteAgentStatusMonitor? = nil) {
        self.integrations = integrations; self.remote = remote
    }
    func sample(config: BarConfig, into state: inout SystemState) {
        state.agents.providers = integrations.filter { config.providerPreferences.includes($0.id) }.map { $0.snapshot() }
        state.agents.providers += remote?.snapshots(enabled: config.providerPreferences.includes("codex") && config.providerPreferences.includes("codexSSH")) ?? []
    }
}

/// Passive local adapter. Codex's on-disk schema is versioned and may change; failures are explicit.
/// Only lifecycle metadata, task names and project directory names are retained. Never starts/resumes tasks or reads authentication files.
final class CodexAgentStatusIntegration: AgentStatusIntegrating {
    let id = "codex"
    private let home: URL
    private let lockIsHeld: (URL) throws -> Bool
    private var legacyCache: [String: (Date, Int, AgentTaskActivity)] = [:]
    init(home: URL? = nil, lockIsHeld: @escaping (URL) throws -> Bool = CodexAgentStatusIntegration.isWriterLockHeld) {
        self.home = home ?? ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        self.lockIsHeld = lockIsHeld
    }
    func snapshot() -> AgentProviderSnapshot {
        var result = AgentProviderSnapshot(id: id, name: "Codex", sampledAt: Date())
        let fm = FileManager.default
        guard fm.fileExists(atPath: home.path) else {
            result.message = "Codex data not found on this Mac"
            return result
        }
        do {
            let lockDirectory = home.appendingPathComponent("thread-writer-locks")
            let lockFiles = fm.fileExists(atPath: lockDirectory.path)
                ? try fm.contentsOfDirectory(at: lockDirectory, includingPropertiesForKeys: nil) : []
            let locks = lockFiles.filter { $0.pathExtension == "lock" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
            // Stale files are common. A live writer must hold the lock before a task is counted.
            let held = try locks.filter(lockIsHeld)
            guard held.count <= 256 else { throw StatusReadError.unavailable }
            let metadata = try AgentStatusDatabase(url: Self.databaseURL(in: home, prefix: "state", fallback: "state_5.sqlite"))
            let columns = try metadata.rows("PRAGMA table_info(threads)").compactMap { $0.count > 1 ? $0[1] : nil }
            let historyColumn = columns.contains("history_mode") ? "history_mode" : "'legacy'"
            var histories: [URL: AgentStatusDatabase] = [:]
            let sourceColumn = columns.contains("source") ? "source" : "''"
            let agentPathColumn = columns.contains("agent_path") ? "agent_path" : "''"
            var retainedPaths = Set<String>()
            for lock in held.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let threadID = lock.deletingPathExtension().lastPathComponent
                let rows = try metadata.rows("SELECT \(historyColumn), rollout_path, \(sourceColumn), \(agentPathColumn) FROM threads WHERE id = ? AND archived = 0", argument: threadID)
                // Ignore ephemeral records and persisted internal workers outside the user task list.
                guard let row = rows.first, row.count == 4, Self.isUserTask(source: row[2], agentPath: row[3]) else { continue }
                let rolloutURL = Self.rolloutURL(row[1], home: home)
                var activity: AgentTaskActivity = .unknown
                var statusDetail = "Unrecognized lifecycle format"
                if row[0] == "paginated" {
                    do {
                        let historyURL = Self.historyDatabaseURL(in: home, rollout: rolloutURL)
                        if histories[historyURL] == nil { histories[historyURL] = try AgentStatusDatabase(url: historyURL) }
                        let turns = try histories[historyURL]?.rows("SELECT status FROM thread_turns WHERE thread_id = ? ORDER BY rollout_ordinal DESC LIMIT 1", argument: threadID)
                        // A freshly created, readable task may not have a first turn yet.
                        // That is idle, while an unfamiliar persisted value remains unknown.
                        activity = turns?.isEmpty == true ? .idle : Self.activity(turnStatus: turns?.first?.first)
                        statusDetail = "No recognized turn status yet"
                    } catch {
                        // A paginated history database can be temporarily inaccessible during
                        // migration or WAL setup. Rollouts also carry the same lifecycle events.
                        // Only use a recognized complete marker; never infer idle from a read error.
                        statusDetail = error.localizedDescription
                        if let rolloutURL {
                            retainedPaths.insert(rolloutURL.path)
                            if let fallback = try? legacyActivity(at: rolloutURL), fallback != .unknown { activity = fallback }
                        }
                    }
                } else if row[0] == "legacy", let rolloutURL {
                    retainedPaths.insert(rolloutURL.path)
                    do {
                        activity = try legacyActivity(at: rolloutURL)
                        statusDetail = "No lifecycle marker in the recent task record"
                    } catch { statusDetail = "Local task record could not be read" }
                }
                // Optional display metadata must never turn a readable lifecycle into an error.
                let details = (try? metadata.rows("SELECT substr(COALESCE(NULLIF(name, ''), title), 1, 240), substr(cwd, 1, 4096) FROM threads WHERE id = ?", argument: threadID))
                    ?? (try? metadata.rows("SELECT substr(title, 1, 240), substr(cwd, 1, 4096) FROM threads WHERE id = ?", argument: threadID))
                let fields = details?.first ?? []
                let title = fields.count == 2 ? AgentTaskStatus.displayText(fields[0]) : ""
                let project = fields.count == 2 && !fields[1].isEmpty ? AgentTaskStatus.displayText(URL(fileURLWithPath: fields[1]).lastPathComponent) : ""
                result.tasks.append(AgentTaskStatus(id: threadID, activity: activity, title: title, project: project, statusDetail: activity == .unknown ? statusDetail : ""))
            }
            legacyCache = legacyCache.filter { retainedPaths.contains($0.key) }
            result.available = true
            result.message = result.unknownCount > 0 ? "Some local task statuses could not be read" : "Tasks on this Mac · includes waiting"
        } catch {
            result.tasks = []
            result.message = (error as? StatusReadError)?.errorDescription ?? "Codex local files could not be read. Check access to the Codex data folder."
        }
        return result
    }
    static func databaseURL(in home: URL, prefix: String, fallback: String) -> URL {
        let files = (try? FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil)) ?? []
        let versioned = files.compactMap { url -> (URL, Int)? in
            let name = url.deletingPathExtension().lastPathComponent
            guard url.pathExtension == "sqlite", name.hasPrefix(prefix + "_"),
                  let version = Int(name.dropFirst(prefix.count + 1)) else { return nil }
            return (url, version)
        }
        if let latest = versioned.max(by: { $0.1 < $1.1 })?.0 { return latest }
        for name in [prefix + ".sqlite", prefix + ".db"] {
            let url = home.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return home.appendingPathComponent(fallback)
    }
    /// Internal workers are persisted too, but do not appear as user tasks in Codex.
    static func isUserTask(source: String, agentPath: String) -> Bool {
        if source == "subagent" { return false }
        if let data = source.data(using: .utf8),
           let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           value["subagent"] != nil { return false }
        // Some versions retain worker ancestry only in agent_path.
        return agentPath.isEmpty || agentPath == "/root"
    }
    static func rolloutURL(_ path: String, home: URL) -> URL? {
        guard !path.isEmpty else { return nil }
        let expanded = (path as NSString).expandingTildeInPath
        return expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : home.appendingPathComponent(expanded)
    }
    static func historyDatabaseURL(in home: URL, rollout: URL?) -> URL {
        let local = databaseURL(in: home, prefix: "thread_history", fallback: "thread_history_1.sqlite")
        if FileManager.default.fileExists(atPath: local.path) { return local }
        // Persisted rollout paths survive CODEX_HOME moves. Recognize only the
        // standard sessions/YYYY/MM/DD layout, without recursively scanning files.
        if let rollout {
            var ancestor = rollout.deletingLastPathComponent()
            for _ in 0..<4 {
                if ancestor.lastPathComponent == "sessions" || ancestor.lastPathComponent == "archived_sessions" {
                    let sibling = databaseURL(in: ancestor.deletingLastPathComponent(), prefix: "thread_history", fallback: "thread_history_1.sqlite")
                    if FileManager.default.fileExists(atPath: sibling.path) { return sibling }
                    break
                }
                ancestor.deleteLastPathComponent()
            }
        }
        return local
    }
    static func activity(turnStatus: String?) -> AgentTaskActivity {
        switch turnStatus {
        case "inProgress": return .active
        case "completed", "failed", "interrupted": return .idle
        default: return .unknown
        }
    }
    static func isWriterLockHeld(_ url: URL) throws -> Bool {
        let fd = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else {
            if errno == ENOENT { return false } // Session ended during enumeration.
            throw StatusReadError.unavailable
        }
        defer { close(fd) }
        if flock(fd, LOCK_SH | LOCK_NB) == 0 {
            _ = flock(fd, LOCK_UN)
            return false
        }
        guard errno == EWOULDBLOCK else { throw StatusReadError.unavailable }
        return true
    }
    private func legacyActivity(at url: URL) throws -> AgentTaskActivity {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let modified = attributes[.modificationDate] as? Date ?? .distantPast
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        if let cached = legacyCache[url.path], cached.0 == modified && cached.1 == size { return cached.2 }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        // Scan backwards in bounded chunks, stopping at the latest lifecycle marker.
        var offset = UInt64(size), tail = Data(), activity: AgentTaskActivity = .unknown
        var scanned = 0
        while offset > 0 && scanned < 8 * 1_048_576 {
            let count = min(offset, 65_536)
            offset -= count
            try handle.seek(toOffset: offset)
            guard let chunk = try handle.read(upToCount: Int(count)), !chunk.isEmpty else { break }
            scanned += chunk.count
            tail.insert(contentsOf: chunk, at: 0)
            activity = Self.legacyActivity(data: tail, startsAtBeginning: offset == 0)
            if activity != .unknown { break }
            // Only carry the incomplete oldest line; complete lines have already been inspected.
            if let newline = tail.firstIndex(of: 10) { tail = Data(tail[...newline]) }
        }
        legacyCache[url.path] = (modified, size, activity)
        return activity
    }
    static func legacyActivity(data: Data, startsAtBeginning: Bool) -> AgentTaskActivity {
        var lines = data.split(separator: 10, omittingEmptySubsequences: false)
        // A trailing partial write must never change the visible lifecycle state.
        if data.last != 10 { _ = lines.popLast() }
        if !startsAtBeginning && !lines.isEmpty { lines.removeFirst() }
        for line in lines.reversed() {
            guard let event = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  event["type"] as? String == "event_msg",
                  let payload = event["payload"] as? [String: Any], let type = payload["type"] as? String else { continue }
            switch type {
            case "task_started": return .active
            case "task_complete", "turn_aborted": return .idle
            default: continue
            }
        }
        return .unknown
    }
}
private enum StatusReadError: LocalizedError {
    case unavailable
    case database(String, Int32)
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Codex writer locks could not be inspected"
        case let .database(file, code):
            if code == SQLITE_BUSY || code == SQLITE_LOCKED { return "\(file) is busy; retrying on the next refresh" }
            return "Cannot read \(file): " + String(cString: sqlite3_errstr(code))
        }
    }
}

/// Prepared, read-only queries; no conversation bodies, prompts, or credentials are selected.
private final class AgentStatusDatabase {
    private var connection: OpaquePointer?
    private let filename: String
    init(url: URL) throws {
        filename = url.lastPathComponent
        guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            let code = sqlite3_errcode(connection)
            sqlite3_close(connection); connection = nil
            throw StatusReadError.database(filename, code)
        }
        sqlite3_busy_timeout(connection, 100)
    }
    deinit { sqlite3_close(connection) }
    func rows(_ sql: String, argument: String? = nil) throws -> [[String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else { throw StatusReadError.database(filename, sqlite3_errcode(connection)) }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        if let argument {
            guard sqlite3_bind_text(statement, 1, argument, -1, transient) == SQLITE_OK else { throw StatusReadError.unavailable }
        }
        var result: [[String]] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW else { throw StatusReadError.database(filename, status) }
            result.append((0..<sqlite3_column_count(statement)).map { index in
                sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
            })
        }
    }
}
