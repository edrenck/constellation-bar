import XCTest
import SQLite3
import Darwin
@testable import ConstellationBar

/// Identical persisted records and real writer locks feed both production readers.
/// This protects against lifecycle drift between the Swift app and SSH Python helper.
final class AgentReaderParityTests: XCTestCase {
    private struct Fixture {
        var title: String
        var turn: String?
        var legacy: String?
        var expected: AgentTaskActivity
    }
    func testProductionReadersAgreeOnSettledActiveWaitingEmptyAndIncompleteRecords() throws {
        let fixtures: [Fixture] = [
            .init(title: "Settled", turn: "completed", expected: .idle),
            .init(title: "Working", turn: "inProgress", expected: .active),
            .init(title: "Approval wait", turn: "inProgress", legacy: event("task_started") + event("exec_approval_request"), expected: .active),
            .init(title: "Input wait", turn: "inProgress", legacy: event("task_started") + event("request_user_input"), expected: .active),
            .init(title: "New empty task", turn: nil, expected: .idle),
            .init(title: "Future turn", turn: "futureStatus", expected: .unknown),
            .init(title: "Legacy waiting", legacy: event("task_started") + event("exec_approval_request"), expected: .active),
            .init(title: "Legacy settled", legacy: event("task_started") + event("task_complete"), expected: .idle),
            .init(title: "Empty legacy", legacy: "", expected: .unknown),
            .init(title: "Malformed legacy", legacy: "{broken JSON}\n", expected: .unknown),
            .init(title: "Incomplete first marker", legacy: String(event("task_started").dropLast()), expected: .unknown),
            .init(title: "Incomplete completion", legacy: event("task_started") + String(event("task_complete").dropLast()), expected: .active)
        ]
        try withFixture(fixtures) { home, ids, python in
            let local = CodexAgentStatusIntegration(home: home).snapshot()
            let remote = try remoteSnapshot(home, python: python)
            XCTAssertTrue(local.available); XCTAssertTrue(remote.available)
            let expected = Dictionary(uniqueKeysWithValues: zip(ids, fixtures.map(\.expected)))
            XCTAssertEqual(Dictionary(uniqueKeysWithValues: local.tasks.map { ($0.id, $0.activity) }), expected)
            XCTAssertEqual(Dictionary(uniqueKeysWithValues: remote.tasks.map { ($0.id, $0.activity) }), expected)
            XCTAssertEqual(local.activeCount, remote.activeCount); XCTAssertEqual(local.idleCount, remote.idleCount)
            XCTAssertEqual(local.unknownCount, remote.unknownCount)
            XCTAssertEqual(local.tasks.map(\.title).sorted(), remote.tasks.map(\.title).sorted())
            XCTAssertTrue(local.tasks.allSatisfy { $0.project == "Parity App" })
        }
    }
    func testHistoryReadErrorsStayUnknownAndMetadataErrorsStayUnavailableInBothReaders() throws {
        try withFixture([.init(title: "History error", turn: "inProgress", expected: .unknown)]) { home, _, python in
            try FileManager.default.removeItem(at: home.appendingPathComponent("thread_history_1.sqlite"))
            var local = CodexAgentStatusIntegration(home: home).snapshot()
            var remote = try remoteSnapshot(home, python: python)
            XCTAssertTrue(local.available); XCTAssertTrue(remote.available)
            XCTAssertEqual(local.unknownCount, 1); XCTAssertEqual(remote.unknownCount, 1)
            XCTAssertEqual(local.idleCount, 0); XCTAssertEqual(remote.idleCount, 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent("thread_history_1.sqlite").path))
            try FileManager.default.removeItem(at: home.appendingPathComponent("state_5.sqlite"))
            local = CodexAgentStatusIntegration(home: home).snapshot(); remote = try remoteSnapshot(home, python: python)
            XCTAssertFalse(local.available); XCTAssertFalse(remote.available)
            XCTAssertTrue(local.tasks.isEmpty); XCTAssertTrue(remote.tasks.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent("state_5.sqlite").path))
        }
    }
    private func event(_ kind: String) -> String { "{\"type\":\"event_msg\",\"payload\":{\"type\":\"\(kind)\"}}\n" }
    private func remoteSnapshot(_ home: URL, python: String) throws -> AgentProviderSnapshot {
        let result = CommandRunner().run(python, ["-c", RemoteAgentProbe.source, home.path], timeout: 5)
        XCTAssertTrue(result.succeeded, result.error)
        let host = CodexSSHHost(hostId: "remote-ssh-codex-managed:parity", displayName: "Parity fixture", hostname: "fixture", alias: nil, sshPort: nil, identity: nil)
        return RemoteAgentStatusMonitor.decode(result, host: host, at: Date())
    }
    private func withFixture(_ fixtures: [Fixture], run: (URL, [String], String) throws -> Void) throws {
        guard let python = ExecutableDiscovery.find("python3") else { throw XCTSkip("Python 3 is required for production-reader parity tests") }
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("thread-writer-locks"), withIntermediateDirectories: true)
        var locks: [Int32] = []
        defer { for descriptor in locks { _ = flock(descriptor, LOCK_UN); close(descriptor) }; try? FileManager.default.removeItem(at: home) }
        try database(home.appendingPathComponent("state_5.sqlite"), "CREATE TABLE threads(id TEXT, history_mode TEXT, rollout_path TEXT, archived INT, title TEXT, cwd TEXT)")
        try database(home.appendingPathComponent("thread_history_1.sqlite"), "CREATE TABLE thread_turns(thread_id TEXT, status TEXT, rollout_ordinal INT)")
        var ids: [String] = []
        for fixture in fixtures {
            let id = UUID().uuidString.lowercased(); ids.append(id)
            let lock = home.appendingPathComponent("thread-writer-locks/\(id).lock")
            let descriptor = open(lock.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
            guard descriptor >= 0 else { throw POSIXError(.EIO) }
            locks.append(descriptor); XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)
            var rollout = ""
            if let legacy = fixture.legacy {
                rollout = "\(id).jsonl"
                try Data(legacy.utf8).write(to: home.appendingPathComponent(rollout))
            }
            let mode = fixture.turn != nil || fixture.legacy == nil ? "paginated" : "legacy"
            try database(home.appendingPathComponent("state_5.sqlite"), "INSERT INTO threads VALUES ('\(id)', '\(mode)', '\(rollout)', 0, '\(fixture.title)', '/Projects/Parity App')")
            if let turn = fixture.turn { try database(home.appendingPathComponent("thread_history_1.sqlite"), "INSERT INTO thread_turns VALUES ('\(id)', '\(turn)', 1)") }
        }
        try run(home, ids, python)
    }
    private func database(_ url: URL, _ sql: String) throws {
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw WidgetActionError(message: String(cString: sqlite3_errmsg(handle))) }
    }
}
