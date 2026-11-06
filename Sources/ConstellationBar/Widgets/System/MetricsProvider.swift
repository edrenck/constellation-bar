import Foundation

final class MetricsProvider: SystemProviding {
    let kinds: Set<WidgetKind> = [.network, .cpu, .memory, .disk, .uptime, .thermal, .system]
    private let reader: MetricsReading
    private let now: () -> TimeInterval
    private var previousNetwork: NetworkCounters?
    private var previousCPU: CPUCounters?
    private var previousSampleTime: TimeInterval?
    init(reader: MetricsReading = HostMetricsReader(), now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.reader = reader; self.now = now
    }
    func sample(config: BarConfig, into state: inout SystemState) {
        state.metricsSampledAt = Date()
        let time = now(), elapsed = max(0.2, time - (previousSampleTime ?? time))
        previousSampleTime = time
        var visible = Set(config.rightWidgets)
        if !visible.isDisjoint(with: [.system, .cpu, .memory]) { visible.formUnion([.cpu, .memory, .network]) }
        if !visible.contains(.network) { previousNetwork = nil }
        if !visible.contains(.cpu) { previousCPU = nil }
        if visible.contains(.network) { state.network = sampleNetwork(elapsed: elapsed) }
        if visible.contains(.cpu) { state.cpu = sampleCPU() }
        if visible.contains(.memory) { state.memory = sampleMemory() }
        if visible.contains(.disk) { state.disk = sampleDisk() }
        if visible.contains(.thermal) || visible.contains(.cpu) { state.thermal = reader.thermal() }
        if visible.contains(.cpu) || visible.contains(.memory) {
            do { state.topProcesses = try reader.processes(); state.topProcessesStatus = .available }
            catch { state.topProcesses = []; state.topProcessesStatus = .failed(error.localizedDescription) }
        }
        state.uptime = ProcessInfo.processInfo.systemUptime
    }
    func sampleNetwork(elapsed: TimeInterval) -> NetworkSpeedState {
        let current: NetworkCounters
        do { current = try reader.network() }
        catch { previousNetwork = nil; return NetworkSpeedState(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0, status: .failed(error.localizedDescription)) }
        defer { previousNetwork = current }
        guard let previous = previousNetwork, current.interfaceNames == previous.interfaceNames,
              current.received >= previous.received, current.sent >= previous.sent,
              elapsed.isFinite, elapsed > 0 else {
            return NetworkSpeedState(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0, status: .waiting)
        }
        func rate(_ difference: UInt64) -> UInt64 {
            UInt64(min(Double(UInt64.max).nextDown, Double(difference)/elapsed))
        }
        return NetworkSpeedState(downloadBytesPerSecond: rate(current.received-previous.received), uploadBytesPerSecond: rate(current.sent-previous.sent), interfaceNames: current.interfaceNames)
    }
    func sampleCPU() -> CPUState {
        let current: CPUCounters
        do { current = try reader.cpu() }
        catch {
            previousCPU = nil
            return CPUState(usage: 0, status: .failed(error.localizedDescription))
        }
        defer { previousCPU = current }
        guard let previous = previousCPU,
              current.user >= previous.user, current.system >= previous.system,
              current.idle >= previous.idle, current.nice >= previous.nice else {
            return CPUState(usage: 0, status: .waiting)
        }
        // Subtract each monotonic component before summing in floating point. Tick reset/wrap
        // starts a new baseline; neither unsigned subtraction nor integer totals can overflow.
        let idle = Double(current.idle-previous.idle)
        let total = Double(current.user-previous.user) + Double(current.system-previous.system)
            + idle + Double(current.nice-previous.nice)
        guard total > 0 else { return CPUState(usage: 0, status: .waiting) }
        return CPUState(usage: max(0, min(100, (1.0 - idle / total) * 100.0)))
    }
    func deactivate() { previousCPU = nil; previousNetwork = nil; previousSampleTime = nil }
    func sampleMemory() -> MemoryState {
        do { return try reader.memory() }
        catch { return MemoryState(usage: 0, status: .failed(error.localizedDescription)) }
    }
    func sampleDisk() -> DiskState {
        do { return try reader.disk() }
        catch { return DiskState(usage: 0, status: .failed(error.localizedDescription)) }
    }
}
