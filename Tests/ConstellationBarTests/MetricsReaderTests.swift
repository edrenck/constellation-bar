import XCTest
@testable import ConstellationBar

final class FixtureMetricsReader: MetricsReading {
    var readCPU: () throws -> CPUCounters = { CPUCounters(user: 10, system: 5, idle: 20, nice: 0) }
    var readNetwork: () throws -> NetworkCounters = { NetworkCounters(received: 100, sent: 50) }
    var readMemory: () throws -> MemoryState = { MemoryState(usage: 50, usedBytes: 500, totalBytes: 1000) }
    var readDisk: () throws -> DiskState = { DiskState(usage: 25, freeBytes: 750, totalBytes: 1000) }
    var readProcesses: () throws -> [ProcessUsage] = { [] }
    func cpu() throws -> CPUCounters { try readCPU() }
    func network() throws -> NetworkCounters { try readNetwork() }
    func memory() throws -> MemoryState { try readMemory() }
    func disk() throws -> DiskState { try readDisk() }
    func processes() throws -> [ProcessUsage] { try readProcesses() }
    func thermal() -> ThermalPressureState { .nominal }
}

final class MetricsReaderTests: XCTestCase {
    func testSystemBaselineResetsWhenDiskKeepsTheProviderActive() {
        let reader = FixtureMetricsReader()
        var time: TimeInterval = 0, counter: UInt64 = 100
        reader.readNetwork = { NetworkCounters(received: counter, sent: counter) }
        let provider = MetricsProvider(reader: reader, now: { time })
        var config = BarConfig.default; config.rightWidgets = [.system, .disk]
        var state = SystemState(); provider.sample(config: config, into: &state)
        time = 10; counter = 200; provider.sample(config: config, into: &state)
        XCTAssertEqual(state.network.downloadBytesPerSecond, 10)
        config.rightWidgets = [.disk]; time = 20; provider.sample(config: config, into: &state)
        config.rightWidgets = [.system, .disk]; time = 30; counter = 10_000; provider.sample(config: config, into: &state)
        XCTAssertEqual(state.network.status, .waiting, "A hidden interval must establish a fresh baseline instead of a transfer spike")
    }
    func testFailureDoesNotBecomeZeroAndIndependentReadingsRecover() {
        let reader = FixtureMetricsReader(), provider = MetricsProvider(reader: reader)
        var config = BarConfig.default; config.rightWidgets = [.system, .disk]
        var state = SystemState(); provider.sample(config: config, into: &state)
        XCTAssertTrue(state.memory.status.isAvailable); XCTAssertEqual(state.memory.usage, 50)
        reader.readMemory = { throw WidgetActionError(message: "Memory fixture failed") }
        reader.readDisk = { throw WidgetActionError(message: "Disk fixture failed") }
        reader.readProcesses = { throw WidgetActionError(message: "Process fixture failed") }
        provider.sample(config: config, into: &state)
        XCTAssertEqual(state.memory.status, .failed("Memory fixture failed"))
        XCTAssertEqual(state.disk.status, .failed("Disk fixture failed"))
        XCTAssertEqual(state.topProcessesStatus, .failed("Process fixture failed")); XCTAssertTrue(state.topProcesses.isEmpty)
        reader.readMemory = { MemoryState(usage: 75, usedBytes: 750, totalBytes: 1000) }
        provider.sample(config: config, into: &state)
        XCTAssertTrue(state.memory.status.isAvailable); XCTAssertEqual(state.memory.usage, 75)
        XCTAssertFalse(state.disk.status.isAvailable)
    }

    func testNetworkFailureAndResetDiscardBaselineAndBoundLargeRates() {
        let reader = FixtureMetricsReader(), provider = MetricsProvider(reader: reader)
        XCTAssertEqual(provider.sampleNetwork(elapsed: 1).status, .waiting)
        reader.readNetwork = { throw WidgetActionError(message: "Network fixture failed") }
        XCTAssertEqual(provider.sampleNetwork(elapsed: 1).status, .failed("Network fixture failed"))
        reader.readNetwork = { NetworkCounters(received: 0, sent: 0) }
        XCTAssertEqual(provider.sampleNetwork(elapsed: 1).status, .waiting)
        reader.readNetwork = { NetworkCounters(received: .max, sent: .max) }
        let large = provider.sampleNetwork(elapsed: 0.2)
        XCTAssertTrue(large.status.isAvailable); XCTAssertGreaterThan(large.downloadBytesPerSecond, 0)
        reader.readNetwork = { NetworkCounters(received: 10, sent: 10) }
        XCTAssertEqual(provider.sampleNetwork(elapsed: 1).status, .waiting)
        reader.readNetwork = { NetworkCounters(received: 20, sent: 30) }
        let recovered = provider.sampleNetwork(elapsed: 2)
        XCTAssertEqual(recovered.downloadBytesPerSecond, 5)
        reader.readNetwork = { NetworkCounters(received: 10_000, sent: 10_000, interfaceNames: ["fixture0"]) }
        XCTAssertEqual(provider.sampleNetwork(elapsed: 1).status, .waiting, "Changing interface ownership establishes a new baseline")
        reader.readNetwork = { NetworkCounters(received: 10_020, sent: 10_030, interfaceNames: ["fixture0"]) }
        XCTAssertEqual(provider.sampleNetwork(elapsed: 2).interfaceNames, ["fixture0"])
    }

    func testFilesystemRejectsMissingInvalidNonfiniteAndOversizedCapacity() throws {
        for attributes: [FileAttributeKey: Any] in [[:], [.systemSize: 0, .systemFreeSize: 0], [.systemSize: 100, .systemFreeSize: 101], [.systemSize: Double.nan, .systemFreeSize: 0], [.systemSize: Double(UInt64.max), .systemFreeSize: 0]] {
            XCTAssertThrowsError(try HostMetricsReader(filesystem: { attributes }).disk())
        }
        let disk = try HostMetricsReader(filesystem: { [.systemSize: 1000, .systemFreeSize: 250] }).disk()
        XCTAssertEqual(disk.usage, 75); XCTAssertEqual(disk.freeBytes, 250)
    }

    func testProcessReaderRejectsPartialMalformedAndNonfiniteOutput() throws {
        for result in [CommandResult(output: "10 2 /bin/sh", status: 1), CommandResult(output: "10 2 /bin/sh", status: 0, outputTruncated: true), CommandResult(output: "nan 2 /bin/sh", status: 0), CommandResult(output: "10 2 /bin/sh\nbad", status: 0)] {
            XCTAssertThrowsError(try HostMetricsReader(runner: MetricsCommandFixture(result: result)).processes())
        }
        let values = try HostMetricsReader(runner: MetricsCommandFixture(result: CommandResult(output: "125 2 /Applications/Worker\n0 0 /bin/sh", status: 0))).processes()
        XCTAssertEqual(values.first?.cpu, 125); XCTAssertEqual(values.first?.name, "Worker")
    }
}

private struct MetricsCommandFixture: CommandRunning {
    let result: CommandResult
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> CommandResult { result }
}
