import XCTest
@testable import ConstellationBar

final class SamplingFailureTests: XCTestCase {
    func testCPUCounterResetDoesNotUnderflow() {
        var readings = [CPUCounters(user: 100, system: 50, idle: 200, nice: 0), CPUCounters(user: 0, system: 0, idle: 0, nice: 0)]
        let reader = FixtureMetricsReader(); reader.readCPU = { readings.removeFirst() }
        let provider = MetricsProvider(reader: reader)
        _ = provider.sampleCPU()
        XCTAssertEqual(provider.sampleCPU().status, .waiting)
    }

    func testCPUFailureClearsBaselineAndRecoveryUsesOnlyNewCounters() {
        enum Failure: LocalizedError { case unavailable; var errorDescription: String? { "Fixture CPU read failed" } }
        var readings: [Result<CPUCounters, Error>] = [.success(CPUCounters(user: 100, system: 50, idle: 200, nice: 0)), .failure(Failure.unavailable), .success(CPUCounters(user: 10, system: 5, idle: 20, nice: 0)), .success(CPUCounters(user: 20, system: 5, idle: 30, nice: 0))]
        let reader = FixtureMetricsReader(); reader.readCPU = { try readings.removeFirst().get() }
        let provider = MetricsProvider(reader: reader)
        XCTAssertEqual(provider.sampleCPU().status, .waiting)
        let failed = provider.sampleCPU()
        XCTAssertEqual(failed.valueText, "—"); XCTAssertFalse(failed.isAvailable)
        XCTAssertTrue(failed.statusDescription.contains("Fixture CPU read failed"))
        XCTAssertEqual(provider.sampleCPU().status, .waiting)
        let recovered = provider.sampleCPU()
        XCTAssertTrue(recovered.isAvailable); XCTAssertEqual(recovered.usage, 50, accuracy: 0.001)
        provider.deactivate()
        readings = [.success(CPUCounters(user: 1000, system: 1000, idle: 1000, nice: 0))]
        XCTAssertEqual(provider.sampleCPU().status, .waiting, "Reactivation must establish a fresh baseline")
    }

    func testIndividualCounterWrapAndLargeCountersStaySafe() {
        var readings = [CPUCounters(user: 100, system: 50, idle: 200, nice: 0), CPUCounters(user: 99, system: 1000, idle: 300, nice: 0), CPUCounters(user: .max, system: .max, idle: .max, nice: .max)]
        let reader = FixtureMetricsReader(); reader.readCPU = { readings.removeFirst() }
        let provider = MetricsProvider(reader: reader)
        _ = provider.sampleCPU()
        XCTAssertEqual(provider.sampleCPU().status, .waiting, "A decreased component resets the baseline even when its total grew")
        let large = provider.sampleCPU()
        XCTAssertTrue(large.isAvailable); XCTAssertTrue(large.usage.isFinite)
        XCTAssertTrue((0...100).contains(large.usage))
    }

    func testVPNRejectsFailedTimedOutAndTruncatedConnectedListings() {
        let listing = "* (Connected) 2794E9B3-B989-4DD0-AE93-0187C138B0AE VPN \"Office\" [VPN]"
        var config = BarConfig.default; config.providerPreferences.disabled = ["tailscale"]
        for result in [CommandResult(output: listing, status: 1), CommandResult(output: listing, status: 0, timedOut: true), CommandResult(output: listing, status: 0, outputTruncated: true)] {
            let runner = SamplingRunner { _, _ in result }
            var state = SystemState(); VPNProvider(runner: runner).sample(config: config, into: &state)
            XCTAssertTrue(state.vpn.connections.isEmpty)
            XCTAssertFalse(state.vpn.available)
            XCTAssertEqual(WidgetCatalog.module(for: .vpn).presentation(state, config, WidgetHistory()).text, "VPN unavailable")
            XCTAssertTrue(state.providerStatuses.contains { $0.id == "systemVPN" && $0.message != "Available" })
        }
        var state = SystemState(); VPNProvider(runner: SamplingRunner { _, _ in CommandResult(status: 0) }).sample(config: config, into: &state)
        XCTAssertTrue(state.vpn.available); XCTAssertTrue(state.vpn.connections.isEmpty)
        XCTAssertEqual(WidgetCatalog.module(for: .vpn).presentation(state, config, WidgetHistory()).text, "VPN off")
        VPNProvider(runner: SamplingRunner { _, _ in CommandResult(status: 1) }).sample(config: config, into: &state)
        XCTAssertFalse(state.vpn.available, "A prior successful sample cannot make a failed read available")
        XCTAssertFalse(state.providerStatuses.contains { $0.id == "systemVPN" && $0.message == "Available" })
    }

    func testVPNControlNeverStartsOrStopsAfterInvalidPreflight() {
        let service = "2794E9B3-B989-4DD0-AE93-0187C138B0AE"
        let listing = "* (Connected) \(service) VPN \"Office\" [VPN]"
        for result in [CommandResult(output: listing, status: 1), CommandResult(output: listing, status: 0, timedOut: true), CommandResult(output: listing, status: 0, outputTruncated: true), CommandResult(status: 0)] {
            let runner = SamplingRunner { _, arguments in
                XCTAssertEqual(arguments, ["--nc", "list"]); return result
            }
            let provider = VPNProvider(runner: runner)
            XCTAssertThrowsError(try provider.setConnected(false, service: service))
            XCTAssertEqual(runner.calls, 1)
        }
    }

    func testVPNCommandsUseTheSampledAdapterAndReportCommandFailure() throws {
        let service = "2794E9B3-B989-4DD0-AE93-0187C138B0AE"
        let listing = "* (Connected) \(service) VPN \"Office\" [VPN]"
        var commands: [[String]] = [], failControl = false
        let runner = SamplingRunner { _, arguments in
            commands.append(arguments)
            return arguments == ["--nc", "list"] ? CommandResult(output: listing, status: 0) : CommandResult(status: failControl ? 1 : 0)
        }
        let provider = VPNProvider(runner: runner), services = WidgetServices(vpn: provider)
        var config = BarConfig.default; config.providerPreferences.disabled = ["tailscale"]
        var state = SystemState(); provider.sample(config: config, into: &state)
        XCTAssertEqual(state.vpn.connections.first?.id, service)
        try services.perform(.vpn(service: service, connected: false))
        XCTAssertEqual(commands, [["--nc", "list"], ["--nc", "list"], ["--nc", "stop", service]])
        failControl = true
        XCTAssertThrowsError(try services.perform(.vpn(service: service, connected: true)))
        XCTAssertEqual(commands.last, ["--nc", "start", service])
    }

    func testHidingAgentWidgetCancelsQueuedHostsThroughSystemMonitor() {
        let started = expectation(description: "first SSH started"), sampled = expectation(description: "agent snapshot published"), hidden = expectation(description: "provider deactivation barrier")
        let gate = DispatchSemaphore(value: 0)
        let runner = SamplingRunner { _, _ in CommandResult(status: 1) }
        runner.body = { _, _ in
            if runner.calls == 1 { started.fulfill(); _ = gate.wait(timeout: .now()+3) }
            return CommandResult(output: #"{"version":1,"available":true,"message":"Connected","tasks":[]}"#, status: 0)
        }
        let hosts = (1...4).map { CodexSSHHost(hostId: "remote-ssh-codex-managed:fixture\($0)", displayName: "Fixture \($0)", hostname: "fixture\($0)", alias: nil, sshPort: nil, identity: nil) }
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        let remote = RemoteAgentStatusMonitor(discover: { hosts }, runner: runner, queue: queue)
        let provider = AgentStatusProvider(integrations: [], remote: remote)
        let monitor = SystemMonitor(providers: [provider])
        var config = BarConfig.default; config.rightWidgets = [.agentStatus]
        var published = false
        monitor.refresh(config: config, generation: 1) { state in
            if state.agents.providers.count == 4, !published { published = true; sampled.fulfill() }
        }
        wait(for: [started, sampled], timeout: 2)
        config.rightWidgets = []
        monitor.refresh(config: config, generation: 2) { XCTAssertTrue($0.agents.providers.isEmpty) }
        monitor.performSetup(kind: .agentStatus, operation: {}) { error in XCTAssertNil(error); hidden.fulfill() }
        wait(for: [hidden], timeout: 2)
        gate.signal(); queue.waitUntilAllOperationsAreFinished()
        XCTAssertEqual(runner.calls, 1, "The three queued probes must never reach the SSH runner after hiding")
        queue.isSuspended = true
        let fresh = remote.snapshots(enabled: true)
        XCTAssertEqual(fresh.count, 4)
        XCTAssertTrue(fresh.allSatisfy { !$0.available }, "A completed probe from the old generation cannot reappear after re-enabling")
        _ = remote.snapshots(enabled: false)
        queue.isSuspended = false; queue.waitUntilAllOperationsAreFinished()
        monitor.stop()
        runner.body = { _, _ in CommandResult(status: 1) }
    }
}

private final class SamplingRunner: CommandRunning {
    private let lock = NSLock()
    private var count = 0
    var body: (String, [String]) -> CommandResult
    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
    init(_ body: @escaping (String, [String]) -> CommandResult) { self.body = body }
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> CommandResult {
        lock.lock(); count += 1; lock.unlock()
        return body(executable, arguments)
    }
}
