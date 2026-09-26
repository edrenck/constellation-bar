import XCTest
import SQLite3
import AppKit
import Darwin
@testable import ConstellationBar

final class AgentStatusTests: XCTestCase {
    private let activeID = "00000000-0000-4000-8000-000000000001"
    private let idleID = "00000000-0000-4000-8000-000000000002"
    private let staleID = "00000000-0000-4000-8000-000000000003"
    private func fixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url.appendingPathComponent("thread-writer-locks"), withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }
    private func database(_ home: URL, _ name: String, sql: String) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(home.appendingPathComponent(name).path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            XCTFail(String(cString: sqlite3_errmsg(db))); return
        }
    }
    private func lockFile(_ home: URL, _ id: String) throws -> URL {
        let url = home.appendingPathComponent("thread-writer-locks/\(id).lock")
        try Data().write(to: url)
        return url
    }
    func testLatestTurnCountsOnlyLivePersistedWorkersAndUpdates() throws {
        let home = try fixture()
        for id in [activeID, idleID, staleID] { _ = try lockFile(home, id) }
        try database(home, "state_5.sqlite", sql: """
        CREATE TABLE threads(id TEXT, history_mode TEXT, rollout_path TEXT, archived INT);
        INSERT INTO threads VALUES ('\(activeID)', 'paginated', '', 0), ('\(idleID)', 'paginated', '', 0), ('\(staleID)', 'paginated', '', 0);
        """)
        try database(home, "thread_history_1.sqlite", sql: """
        CREATE TABLE thread_turns(thread_id TEXT, status TEXT, rollout_ordinal INT);
        INSERT INTO thread_turns VALUES ('\(activeID)', 'completed', 1), ('\(activeID)', 'inProgress', 2),
        ('\(idleID)', 'inProgress', 1), ('\(idleID)', 'completed', 2), ('\(staleID)', 'inProgress', 1);
        """)
        let stale = staleID
        let integration = CodexAgentStatusIntegration(home: home, lockIsHeld: { $0.deletingPathExtension().lastPathComponent != stale })
        var snapshot = integration.snapshot()
        XCTAssertTrue(snapshot.available)
        XCTAssertEqual(snapshot.tasks.count, 2)
        XCTAssertEqual(snapshot.activeCount, 1)
        XCTAssertEqual(snapshot.idleCount, 1)
        try database(home, "thread_history_1.sqlite", sql: "UPDATE thread_turns SET status = 'interrupted' WHERE thread_id = '\(activeID)' AND rollout_ordinal = 2")
        snapshot = integration.snapshot()
        XCTAssertEqual(snapshot.activeCount, 0)
        XCTAssertEqual(snapshot.idleCount, 2)
        try FileManager.default.removeItem(at: home.appendingPathComponent("state_5.sqlite"))
        snapshot = integration.snapshot()
        XCTAssertFalse(snapshot.available)
        XCTAssertTrue(snapshot.tasks.isEmpty, "Never retain a stale active count after a failed read")
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent("state_5.sqlite").path), "Read-only open must not recreate missing databases")
    }
    func testVersionedDatabasesAndLegacySchemaWithoutHistoryColumn() throws {
        let home = try fixture()
        _ = try lockFile(home, activeID)
        try database(home, "state_6.sqlite", sql: "CREATE TABLE threads(id TEXT, history_mode TEXT, rollout_path TEXT, archived INT); INSERT INTO threads VALUES ('\(activeID)', 'paginated', '', 0)")
        try database(home, "thread_history_2.sqlite", sql: "CREATE TABLE thread_turns(thread_id TEXT, status TEXT, rollout_ordinal INT); INSERT INTO thread_turns VALUES ('\(activeID)', 'inProgress', 1)")
        let integration = CodexAgentStatusIntegration(home: home, lockIsHeld: { _ in true })
        XCTAssertTrue(integration.snapshot().available)
        XCTAssertEqual(integration.snapshot().activeCount, 1)
        let rollout = home.appendingPathComponent("rollout.jsonl")
        try Data("{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\"}}\n".utf8).write(to: rollout)
        try database(home, "state_6.sqlite", sql: "ALTER TABLE threads DROP COLUMN history_mode; UPDATE threads SET rollout_path = '\(rollout.path)'")
        XCTAssertEqual(integration.snapshot().activeCount, 1)
        XCTAssertTrue(integration.snapshot().available)
    }
    func testFreshCodexInstallWithoutWriterDirectoryIsReadableAndIdle() throws {
        let home = try fixture()
        try FileManager.default.removeItem(at: home.appendingPathComponent("thread-writer-locks"))
        try database(home, "state_5.sqlite", sql: "CREATE TABLE threads(id TEXT, rollout_path TEXT, archived INT)")
        let snapshot = CodexAgentStatusIntegration(home: home).snapshot()
        XCTAssertTrue(snapshot.available)
        XCTAssertTrue(snapshot.tasks.isEmpty)
    }

    func testTaskNamesProjectsAndLiveRenamesUseOptionalMetadata() throws {
        let home = try fixture()
        _ = try lockFile(home, activeID)
        try database(home, "state_5.sqlite", sql: """
        CREATE TABLE threads(id TEXT, history_mode TEXT, rollout_path TEXT, archived INT, title TEXT, cwd TEXT, name TEXT);
        INSERT INTO threads VALUES ('\(activeID)', 'paginated', '', 0, 'Original title', '/Projects/My App', 'Renamed task');
        """)
        try database(home, "thread_history_1.sqlite", sql: """
        CREATE TABLE thread_turns(thread_id TEXT, status TEXT, rollout_ordinal INT);
        INSERT INTO thread_turns VALUES ('\(activeID)', 'inProgress', 1);
        """)
        let integration = CodexAgentStatusIntegration(home: home, lockIsHeld: { _ in true })
        let first = try XCTUnwrap(integration.snapshot().tasks.first)
        XCTAssertEqual(first.displayTitle, "Renamed task")
        XCTAssertEqual(first.project, "My App")
        try database(home, "state_5.sqlite", sql: "UPDATE threads SET name = NULL, title = 'Updated title'")
        XCTAssertEqual(integration.snapshot().tasks.first?.displayTitle, "Updated title")
        try database(home, "state_5.sqlite", sql: "ALTER TABLE threads DROP COLUMN name")
        XCTAssertEqual(integration.snapshot().tasks.first?.displayTitle, "Updated title")
    }
    func testInternalWorkersAreExcludedEvenWhenPersistedAndLocked() throws {
        let home = try fixture()
        for id in [activeID, idleID, staleID] { _ = try lockFile(home, id) }
        try database(home, "state_5.sqlite", sql: """
        CREATE TABLE threads(id TEXT, history_mode TEXT, rollout_path TEXT, archived INT, source TEXT, agent_path TEXT);
        INSERT INTO threads VALUES
        ('\(activeID)', 'paginated', '', 0, 'vscode', NULL),
        ('\(idleID)', 'paginated', '', 0, '{"subagent":{"thread_spawn":{"parent_thread_id":"parent"}}}', '/root/worker'),
        ('\(staleID)', 'paginated', '', 0, '{"subagent":{"other":"guardian"}}', NULL);
        """)
        try database(home, "thread_history_1.sqlite", sql: """
        CREATE TABLE thread_turns(thread_id TEXT, status TEXT, rollout_ordinal INT);
        INSERT INTO thread_turns VALUES ('\(activeID)', 'inProgress', 1), ('\(idleID)', 'inProgress', 1), ('\(staleID)', 'inProgress', 1);
        """)
        let snapshot = CodexAgentStatusIntegration(home: home, lockIsHeld: { _ in true }).snapshot()
        XCTAssertEqual(snapshot.tasks.map(\.id), [activeID])
        XCTAssertEqual(snapshot.activeCount, 1)
        XCTAssertFalse(CodexAgentStatusIntegration.isUserTask(source: "vscode", agentPath: "/root/worker"))
        XCTAssertTrue(CodexAgentStatusIntegration.isUserTask(source: "vscode", agentPath: "/root"))
    }
    func testPaginatedHistoryFailureFallsBackOnlyToRecognizedCompleteLifecycle() throws {
        let home = try fixture()
        _ = try lockFile(home, activeID)
        let rollout = home.appendingPathComponent("rollout.jsonl")
        try database(home, "state_5.sqlite", sql: """
        CREATE TABLE threads(id TEXT, history_mode TEXT, rollout_path TEXT, archived INT);
        INSERT INTO threads VALUES ('\(activeID)', 'paginated', 'rollout.jsonl', 0);
        """)
        let integration = CodexAgentStatusIntegration(home: home, lockIsHeld: { _ in true })
        try Data("{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\"}}\n".utf8).write(to: rollout)
        XCTAssertEqual(integration.snapshot().activeCount, 1)
        try Data("{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\"}}\n".utf8).write(to: rollout)
        XCTAssertEqual(integration.snapshot().idleCount, 1)
        try Data("{\"type\":\"event_msg\",\"payload\":{\"type\":\"future_marker\"}}\n".utf8).write(to: rollout)
        XCTAssertEqual(integration.snapshot().unknownCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent("thread_history_1.sqlite").path))
    }
    func testMovedHomeResolvesHistoryBesidePersistedRolloutAndUnversionedDatabases() throws {
        let home = try fixture(), previousHome = try fixture()
        _ = try lockFile(home, activeID)
        let rollout = previousHome.appendingPathComponent("sessions/2026/09/26/rollout.jsonl")
        try database(home, "state.sqlite", sql: """
        CREATE TABLE threads(id TEXT, history_mode TEXT, rollout_path TEXT, archived INT);
        INSERT INTO threads VALUES ('\(activeID)', 'paginated', '\(rollout.path)', 0);
        """)
        try database(previousHome, "thread_history.db", sql: """
        CREATE TABLE thread_turns(thread_id TEXT, status TEXT, rollout_ordinal INT);
        INSERT INTO thread_turns VALUES ('\(activeID)', 'inProgress', 1);
        """)
        let snapshot = CodexAgentStatusIntegration(home: home, lockIsHeld: { _ in true }).snapshot()
        XCTAssertTrue(snapshot.available)
        XCTAssertEqual(snapshot.activeCount, 1)
        XCTAssertEqual(snapshot.unknownCount, 0)
    }
    func testTaskOrderingFallbackAndWhitespace() {
        let provider = AgentProviderSnapshot(id: "test", name: "Test", tasks: [
            .init(id: "idle", activity: .idle, title: "A"),
            .init(id: "unknown", activity: .unknown, title: "B"),
            .init(id: "active-z", activity: .active, title: "Z"),
            .init(id: "active-a", activity: .active, title: "A")
        ])
        XCTAssertEqual(provider.sortedTasks.map(\.id), ["active-a", "active-z", "unknown", "idle"])
        XCTAssertTrue(AgentTaskStatus(id: activeID, activity: .idle).displayTitle.hasPrefix("Untitled task"))
        XCTAssertEqual(AgentTaskStatus.displayText("  One\n\t two  "), "One two")
    }
    func testUnknownStatusesAndMissingHistoryStayUnknown() throws {
        let home = try fixture()
        _ = try lockFile(home, activeID)
        try database(home, "state_5.sqlite", sql: "CREATE TABLE threads(id TEXT, history_mode TEXT, rollout_path TEXT, archived INT); INSERT INTO threads VALUES ('\(activeID)', 'paginated', '', 0)")
        let integration = CodexAgentStatusIntegration(home: home, lockIsHeld: { _ in true })
        XCTAssertEqual(integration.snapshot().unknownCount, 1)
        XCTAssertTrue(integration.snapshot().tasks[0].statusDetail.contains("thread_history_1.sqlite"))
        XCTAssertEqual(CodexAgentStatusIntegration.activity(turnStatus: "futureStatus"), .unknown)
        XCTAssertEqual(CodexAgentStatusIntegration.activity(turnStatus: "failed"), .idle)
    }
    func testReadableTaskWithNoTurnsIsIdleButUnknownPersistedStatusIsNot() throws {
        let home = try fixture()
        _ = try lockFile(home, activeID)
        try database(home, "state_5.sqlite", sql: "CREATE TABLE threads(id TEXT, history_mode TEXT, rollout_path TEXT, archived INT); INSERT INTO threads VALUES ('\(activeID)', 'paginated', '', 0)")
        try database(home, "thread_history_1.sqlite", sql: "CREATE TABLE thread_turns(thread_id TEXT, status TEXT, rollout_ordinal INT)")
        let integration = CodexAgentStatusIntegration(home: home, lockIsHeld: { _ in true })
        XCTAssertEqual(integration.snapshot().idleCount, 1)
        XCTAssertEqual(integration.snapshot().unknownCount, 0)
        try database(home, "thread_history_1.sqlite", sql: "INSERT INTO thread_turns VALUES ('\(activeID)', 'futureStatus', 1)")
        XCTAssertEqual(integration.snapshot().idleCount, 0)
        XCTAssertEqual(integration.snapshot().unknownCount, 1)
    }
    func testLegacyLifecycleIgnoresContentAndPartialWrites() {
        func event(_ type: String) -> String { "{\"type\":\"event_msg\",\"payload\":{\"type\":\"\(type)\"}}\n" }
        let started = event("task_started")
        XCTAssertEqual(CodexAgentStatusIntegration.legacyActivity(data: Data((started + event("token_count")).utf8), startsAtBeginning: true), .active)
        XCTAssertEqual(CodexAgentStatusIntegration.legacyActivity(data: Data((started + event("task_complete")).utf8), startsAtBeginning: true), .idle)
        XCTAssertEqual(CodexAgentStatusIntegration.legacyActivity(data: Data((started + event("turn_aborted")).utf8), startsAtBeginning: true), .idle)
        XCTAssertEqual(CodexAgentStatusIntegration.legacyActivity(data: Data((started + event("task_complete").dropLast()).utf8), startsAtBeginning: true), .active)
        XCTAssertEqual(CodexAgentStatusIntegration.legacyActivity(data: Data(started.utf8), startsAtBeginning: false), .unknown)
    }
    func testLegacyReaderCrossesChunkBoundariesAndInvalidatesCache() throws {
        let home = try fixture()
        _ = try lockFile(home, activeID)
        let log = home.appendingPathComponent("rollout.jsonl")
        let started = "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\"}}\n"
        let complete = "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\"}}\n"
        let filler = "{\"type\":\"response_item\",\"payload\":\"" + String(repeating: "x", count: 150_000) + "\"}\n"
        try Data((started + filler).utf8).write(to: log)
        try database(home, "state_5.sqlite", sql: "CREATE TABLE threads(id TEXT, history_mode TEXT, rollout_path TEXT, archived INT); INSERT INTO threads VALUES ('\(activeID)', 'legacy', '\(log.path)', 0)")
        let integration = CodexAgentStatusIntegration(home: home, lockIsHeld: { _ in true })
        XCTAssertEqual(integration.snapshot().activeCount, 1)
        XCTAssertEqual(integration.snapshot().activeCount, 1)
        try Data((started + filler + complete).utf8).write(to: log)
        XCTAssertEqual(integration.snapshot().idleCount, 1)
    }
    func testRealLocksRejectStaleFilesWithoutChangingThem() throws {
        let home = try fixture(), url = try lockFile(home, activeID)
        XCTAssertFalse(try CodexAgentStatusIntegration.isWriterLockHeld(url))
        let fd = open(url.path, O_RDONLY)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)
        XCTAssertTrue(try CodexAgentStatusIntegration.isWriterLockHeld(url))
        XCTAssertEqual(flock(fd, LOCK_UN), 0)
        XCTAssertFalse(try CodexAgentStatusIntegration.isWriterLockHeld(url))
        XCTAssertEqual(try Data(contentsOf: url), Data())
    }
    func testDisabledAdaptersAreNotReadAndMultipleProvidersAggregate() {
        let codex = AgentStub(id: "codex"), future = AgentStub(id: "future")
        let provider = AgentStatusProvider(integrations: [codex, future])
        var config = BarConfig.default, state = SystemState()
        config.providerPreferences.disabled = ["codex"]
        provider.sample(config: config, into: &state)
        XCTAssertEqual(codex.calls, 0)
        XCTAssertEqual(future.calls, 1)
        XCTAssertEqual(state.agents.providers.map(\.id), ["future"])
        config.providerPreferences.disabled = []
        provider.sample(config: config, into: &state)
        XCTAssertEqual(state.agents.activeCount, 2)
        XCTAssertTrue(state.agents.isComplete)
        state.agents.providers[0].available = false
        XCTAssertFalse(state.agents.isComplete)
        XCTAssertEqual(WidgetCatalog.module(for: .agentStatus).presentation(state, config, WidgetHistory()).text, "Agents 1 active")
    }
    func testPartialStatusKeepsKnownActiveCountVisible() {
        var state = SystemState()
        state.agents.providers = [.init(id: "codex", name: "Codex", tasks: [
            .init(id: "active", activity: .active), .init(id: "unknown", activity: .unknown)
        ], available: true)]
        let partial = WidgetCatalog.presentation(for: .agentStatus, system: state, config: .default, history: WidgetHistory())
        XCTAssertEqual(partial.text, "Agents 1 active · 1 unknown")
        XCTAssertEqual(partial.compactText, "1+?")
        state.agents.providers[0].available = false
        let unavailable = WidgetCatalog.presentation(for: .agentStatus, system: state, config: .default, history: WidgetHistory())
        XCTAssertEqual(unavailable.text, "Agents status unavailable")
        XCTAssertEqual(unavailable.compactText, "—")
    }
    func testOfflineSavedHostsDoNotObscureReadableTaskActivity() {
        var state = SystemState()
        state.agents.providers = [
            .init(id: "codex", name: "Codex", tasks: [.init(id: "active", activity: .active)], available: true),
            .init(id: "codex:ssh-work", name: "Codex", message: "SSH timed out · host may be offline", sampledAt: Date(), hostName: "Work Mac"),
            .init(id: "codex:ssh-new", name: "Codex", message: "Connecting over SSH…", hostName: "Build Mac")
        ]
        let config = BarConfig.default
        let display = WidgetCatalog.presentation(for: .agentStatus, system: state, config: config, history: WidgetHistory())
        XCTAssertFalse(state.agents.isComplete, "Diagnostics must still identify incomplete host coverage")
        XCTAssertEqual(display.text, "Agents 1 active")
        XCTAssertEqual(display.compactText, "1")
        XCTAssertEqual(display.accent, config.theme.green)
        XCTAssertTrue(display.detail?.contains("Counts from 1 of 3 configured hosts") == true)
        XCTAssertTrue(display.detail?.contains("Work Mac: SSH timed out") == true)
        XCTAssertTrue(display.detail?.contains("Build Mac: Connecting") == true)
        XCTAssertEqual(state.agents.taskSummary, "1 active task")
        state.agents.providers[0].tasks = []
        XCTAssertEqual(state.agents.taskSummary, "No tasks running on checked hosts")
        state.agents.providers[0].available = false
        XCTAssertEqual(state.agents.taskSummary, "Status unavailable")
    }
    func testCompactWidgetKeepsCountAndUpdatesWithoutLosingTooltip() throws {
        _ = NSApplication.shared
        let view = ModernWidgetView(kind: .agentStatus)
        view.update(icon: "person.2", text: "Codex 2 active", accent: .systemGreen, detail: "2 active local tasks", compactText: "2")
        view.setCompactPresentation(true)
        let label = try XCTUnwrap(view.subviews.compactMap { $0 as? NSTextField }.first)
        XCTAssertFalse(label.isHidden)
        XCTAssertEqual(label.stringValue, "2")
        XCTAssertGreaterThan(view.intrinsicContentSize.width, 32)
        XCTAssertEqual(view.toolTip, "2 active local tasks")
        view.update(icon: "person.2", text: "Codex 0 active", accent: .gray, compactText: "0")
        XCTAssertEqual(label.stringValue, "0")
        view.setCompactPresentation(false)
        XCTAssertEqual(label.stringValue, "Codex 0 active")
    }
    func testSystemMigrationPreservesOrderAndPerDisplayOverrides() throws {
        let config = try BarConfig.decode(Data(#"{"schemaVersion":3,"rightWidgets":["battery","memory","cpu","system","network","agentStatus"],"displayOverrides":{"external":{"widgets":["cpu","dateTime","memory"]}}}"#.utf8))
        XCTAssertEqual(config.rightWidgets, [.battery, .system, .agentStatus])
        XCTAssertEqual(config.forDisplay("external").rightWidgets, [.system, .dateTime])
        XCTAssertEqual(config.widgetPreferences.systemMetrics, [.cpu, .memory, .network])
        XCTAssertEqual(try BarConfig.decode(config.encoded()).rightWidgets, config.rightWidgets)
        XCTAssertFalse(WidgetKind.selectableCases.contains(.cpu))
        XCTAssertFalse(WidgetKind.selectableCases.contains(.memory))
        XCTAssertFalse(WidgetKind.selectableCases.contains(.network))
        XCTAssertFalse(WidgetKind.selectableCases.contains(.thermal))
        XCTAssertEqual(WidgetKind.selectableCases.filter { $0 == .system }.count, 1)
    }
}
private final class AgentStub: AgentStatusIntegrating {
    let id: String
    var calls = 0
    init(id: String) { self.id = id }
    func snapshot() -> AgentProviderSnapshot {
        calls += 1
        return AgentProviderSnapshot(id: id, name: id, tasks: [.init(id: "task", activity: .active)], available: true)
    }
}
