import AppKit

final class MetricsProvider: SystemProviding {
    let kinds: Set<WidgetKind> = [.network, .cpu, .memory, .disk, .uptime, .thermal, .system]
    private var previousNetwork: NetworkCounters?
    private var previousCPU: CPUCounters?
    private var previousSampleDate = Date()
    func sample(config: BarConfig, into state: inout SystemState) {
        let now = Date()
        let elapsed = max(0.2, now.timeIntervalSince(previousSampleDate))
        previousSampleDate = now
        var visible = Set(config.rightWidgets)
        if !visible.isDisjoint(with: [.system, .cpu, .memory]) { visible.formUnion([.cpu, .memory, .network]) }
        if visible.contains(.network) { state.network = sampleNetwork(elapsed: elapsed) }
        if visible.contains(.cpu) { state.cpu = sampleCPU() }
        if visible.contains(.memory) { state.memory = sampleMemory() }
        if visible.contains(.disk) { state.disk = sampleDisk() }
        if visible.contains(.thermal) || visible.contains(.cpu) { state.thermal = sampleThermalPressure() }
        if visible.contains(.cpu) || visible.contains(.memory) { state.topProcesses = sampleTopProcesses() }
        state.uptime = ProcessInfo.processInfo.systemUptime
    }
    func sampleNetwork(elapsed: TimeInterval) -> NetworkSpeedState {
        let current = NetworkInterfaceProvider.counters()
        defer { previousNetwork = current }
        guard let previous = previousNetwork else { return NetworkSpeedState(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0) }
        let down = current.received > previous.received ? current.received - previous.received : 0
        let up = current.sent > previous.sent ? current.sent - previous.sent : 0
        return NetworkSpeedState(downloadBytesPerSecond: UInt64(Double(down) / elapsed), uploadBytesPerSecond: UInt64(Double(up) / elapsed))
    }
    func sampleCPU() -> CPUState {
        let current = CPUCounters.current()
        defer { previousCPU = current }
        guard let previous = previousCPU else { return CPUState(usage: 0) }
        let total = Double(max(1, current.total - previous.total))
        let idle = Double(current.idle - previous.idle)
        return CPUState(usage: max(0, min(100, (1.0 - idle / total) * 100.0)))
    }
    func sampleMemory() -> MemoryState {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return MemoryState(usage: 0) }
        let pages = UInt64(statistics.active_count)
            + UInt64(statistics.wire_count)
            + UInt64(statistics.compressor_page_count)
        let used = pages * UInt64(vm_kernel_page_size)
        let total = max(1, ProcessInfo.processInfo.physicalMemory)
        return MemoryState(activeBytes: UInt64(statistics.active_count) * UInt64(vm_kernel_page_size), wiredBytes: UInt64(statistics.wire_count) * UInt64(vm_kernel_page_size), compressedBytes: UInt64(statistics.compressor_page_count) * UInt64(vm_kernel_page_size), usage: min(100, Double(used) / Double(total) * 100), usedBytes: used, totalBytes: total)
    }
    func sampleDisk() -> DiskState {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
              let total = (attributes[.systemSize] as? NSNumber)?.doubleValue,
              let free = (attributes[.systemFreeSize] as? NSNumber)?.doubleValue,
              total > 0 else {
            return DiskState(usage: 0)
        }
        return DiskState(
            usage: min(100, max(0, (total - free) / total * 100)),
            freeBytes: UInt64(max(0, free)),
            totalBytes: UInt64(max(0, total))
        )
    }
    func sampleTopProcesses() -> [ProcessUsage] {
        let output = runCommand("/bin/ps", ["-axo", "pcpu=,pmem=,comm="], timeout: 0.7)
        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(maxSplits: 2, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count == 3, let cpu = Double(parts[0]), let memory = Double(parts[1]) else { return nil }
            let path = String(parts[2])
            return ProcessUsage(name: URL(fileURLWithPath: path).lastPathComponent, cpu: cpu, memory: memory)
        }
        .sorted { $0.cpu > $1.cpu }
        .map { $0 }
    }
    func sampleThermalPressure() -> ThermalPressureState {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .nominal
        }
    }
    func runCommand(_ executable: String, _ args: [String], timeout: TimeInterval = 1) -> String {
        let result = CommandRunner().run(executable, args, timeout: timeout)
        return result.succeeded ? result.output : ""
    }
}
