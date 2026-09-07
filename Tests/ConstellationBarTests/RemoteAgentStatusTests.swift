import XCTest
@testable import ConstellationBar

final class RemoteAgentStatusTests: XCTestCase {
    private let host = CodexSSHHost(hostId: "remote-ssh-codex-managed:build", displayName: "Build Mac", hostname: "user@build", alias: nil, sshPort: 2222, identity: "/tmp/key with spaces")
    private let taskID = "00000000-0000-4000-8000-000000000001"
    private var good: CommandResult {
        CommandResult(output: """
        {"version":1,"available":true,"message":"Connected","tasks":[{"id":"\(taskID)","activity":"active","title":"Build app","project":"App","statusDetail":""}]}
        """, status: 0)
    }
    func testDiscoveryUsesOnlyCodexManagedConnectionsAndRejectsInvalidDestinations() throws {
        let json = #"{"unrelated":"ignored","codex-managed-remote-connections":[{"hostId":"remote-ssh-codex-managed:build","displayName":"Build Mac","hostname":"user@build","alias":null,"sshPort":2222,"identity":"/tmp/key with spaces"}]}"#
        XCTAssertEqual(try CodexSSHHost.decode(Data(json.utf8)), [host])
        XCTAssertEqual(try CodexSSHHost.decode(Data("{}".utf8)), [])
        XCTAssertThrowsError(try CodexSSHHost.decode(Data(json.replacingOccurrences(of: "user@build", with: "-oProxyCommand=bad").utf8)))
        XCTAssertThrowsError(try CodexSSHHost.decode(Data(json.replacingOccurrences(of: "2222", with: "70000").utf8)))
    }
    func testSSHArgumentsKeepHostAndIdentityOutOfRemoteShellAndDoNotPrompt() {
        let args = RemoteAgentStatusMonitor.arguments(for: host)
        XCTAssertTrue(args.contains("BatchMode=yes"))
        XCTAssertTrue(args.contains("StrictHostKeyChecking=yes"))
        XCTAssertTrue(args.contains("ClearAllForwardings=yes"))
        XCTAssertTrue(args.contains("/tmp/key with spaces"))
        XCTAssertEqual(args[args.count - 2], "user@build")
        XCTAssertFalse(args.last!.contains("user@build"))
        XCTAssertFalse(args.last!.contains("/tmp/key"))
    }
    func testOfflineInvalidAndUnknownResponsesNeverBecomeZeroSuccessfulTasks() {
        let date = Date()
        let success = RemoteAgentStatusMonitor.decode(good, host: host, at: date)
        XCTAssertEqual(success.activeCount, 1)
        XCTAssertEqual(success.hostName, "Build Mac")
        XCTAssertEqual(success.sampledAt, date)
        for result in [CommandResult(timedOut: true), CommandResult(output: "not JSON", status: 0), CommandResult(output: good.output.replacingOccurrences(of: "\"version\":1", with: "\"version\":2"), status: 0)] {
            let snapshot = RemoteAgentStatusMonitor.decode(result, host: host, at: date)
            XCTAssertFalse(snapshot.available)
            XCTAssertTrue(snapshot.tasks.isEmpty)
        }
        let unknown = RemoteAgentStatusMonitor.decode(CommandResult(output: good.output.replacingOccurrences(of: "\"active\"", with: "\"unknown\""), status: 0), host: host, at: date)
        XCTAssertTrue(unknown.available)
        XCTAssertEqual(unknown.unknownCount, 1)
    }
    func testSlowRemoteDoesNotBlockSamplingAndDisableDiscardsItsResult() {
        let started = expectation(description: "SSH started")
        let gate = DispatchSemaphore(value: 0)
        let result = good
        let runner = RemoteRunnerStub {
            started.fulfill()
            _ = gate.wait(timeout: .now() + 3)
            return result
        }
        let monitor = RemoteAgentStatusMonitor(discover: { [self.host] }, runner: runner)
        XCTAssertTrue(monitor.snapshots(enabled: false).isEmpty)
        // Returning while the runner is waiting proves that sampling does not wait on SSH.
        XCTAssertFalse(monitor.snapshots(enabled: true)[0].available)
        wait(for: [started], timeout: 2)
        XCTAssertTrue(monitor.snapshots(enabled: false).isEmpty)
        gate.signal()
        XCTAssertTrue(monitor.snapshots(enabled: false).isEmpty)
    }
    func testRemotePythonProbeReadsLivePersistedTasksOnly() throws {
        guard let python = ExecutableDiscovery.find("python3") else { throw XCTSkip("Python 3 required for helper integration test") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = #"""
import pathlib,sys,sqlite3,fcntl
h=pathlib.Path(sys.argv[1]); (h/'thread-writer-locks').mkdir(parents=True)
active='00000000-0000-4000-8000-000000000001'
stale='00000000-0000-4000-8000-000000000002'
held=(h/'thread-writer-locks'/(active+'.lock')).open('w'); fcntl.flock(held,fcntl.LOCK_EX)
(h/'thread-writer-locks'/(stale+'.lock')).touch()
with sqlite3.connect(h/'state_5.sqlite') as d:
 d.execute('CREATE TABLE threads(id, history_mode, rollout_path, archived, title, cwd)')
 for tid in [active,stale]: d.execute('INSERT INTO threads VALUES (?, ?, ?, ?, ?, ?)',(tid,'paginated','',0,'Remote task','/projects/App'))
with sqlite3.connect(h/'thread_history_1.sqlite') as d:
 d.execute('CREATE TABLE thread_turns(thread_id,status,rollout_ordinal)')
 d.execute('INSERT INTO thread_turns VALUES (?, ?, ?)',(active,'inProgress',1))
"""#
        let result = CommandRunner().run(python, ["-c", fixture + "\n" + RemoteAgentProbe.source, root.path], timeout: 5)
        XCTAssertTrue(result.succeeded, result.error)
        let snapshot = RemoteAgentStatusMonitor.decode(result, host: host, at: Date())
        XCTAssertTrue(snapshot.available)
        XCTAssertEqual(snapshot.tasks.count, 1)
        XCTAssertEqual(snapshot.activeCount, 1)
        XCTAssertEqual(snapshot.tasks.first?.title, "Remote task")
        XCTAssertEqual(snapshot.tasks.first?.project, "App")
    }
}
private struct RemoteRunnerStub: CommandRunning {
    let action: () -> CommandResult
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> CommandResult { action() }
}
