import Foundation
import Darwin

protocol MetricsReading {
    func cpu() throws -> CPUCounters
    func network() throws -> NetworkCounters
    func memory() throws -> MemoryState
    func disk() throws -> DiskState
    func processes() throws -> [ProcessUsage]
    func thermal() -> ThermalPressureState
}

/// The OS adapter owns Mach, filesystem and process access; providers own sampling baselines.
struct HostMetricsReader: MetricsReading {
    private let runner: CommandRunning
    private let filesystem: () throws -> [FileAttributeKey: Any]
    init(runner: CommandRunning = CommandRunner(), filesystem: @escaping () throws -> [FileAttributeKey: Any] = { try FileManager.default.attributesOfFileSystem(forPath: "/") }) {
        self.runner = runner; self.filesystem = filesystem
    }
    func cpu() throws -> CPUCounters { try CPUCounters.current() }
    func network() throws -> NetworkCounters { try NetworkInterfaceProvider.counters() }
    func memory() throws -> MemoryState {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(host, HOST_VM_INFO64, $0, &count) }
        }
        guard result == KERN_SUCCESS else { throw WidgetActionError(message: "Memory read failed (macOS error \(result)). Retrying with the next sample.") }
        let active = UInt64(statistics.active_count) * UInt64(vm_kernel_page_size)
        let wired = UInt64(statistics.wire_count) * UInt64(vm_kernel_page_size)
        let compressed = UInt64(statistics.compressor_page_count) * UInt64(vm_kernel_page_size)
        let used = active + wired + compressed, total = ProcessInfo.processInfo.physicalMemory
        guard total > 0 else { throw WidgetActionError(message: "macOS did not report physical memory capacity.") }
        return MemoryState(activeBytes: active, wiredBytes: wired, compressedBytes: compressed, usage: min(100, Double(used)/Double(total)*100), usedBytes: used, totalBytes: total)
    }
    func disk() throws -> DiskState {
        let attributes = try filesystem()
        guard let total = (attributes[.systemSize] as? NSNumber)?.doubleValue,
              let free = (attributes[.systemFreeSize] as? NSNumber)?.doubleValue,
              total.isFinite, free.isFinite, total > 0, free >= 0, free <= total,
              total < Double(UInt64.max) else {
            throw WidgetActionError(message: "Disk capacity is unavailable or invalid. Retrying with the next sample.")
        }
        return DiskState(usage: (total-free)/total*100, freeBytes: UInt64(free), totalBytes: UInt64(total))
    }
    func processes() throws -> [ProcessUsage] {
        let result = runner.run("/bin/ps", ["-axo", "pcpu=,pmem=,comm="], timeout: 0.7)
        guard result.succeeded else { throw WidgetActionError(message: "Process list could not be read completely. Retrying with the next sample.") }
        return try result.output.split(whereSeparator: \.isNewline).map { line in
            let parts = line.split(maxSplits: 2, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count == 3, let cpu = Double(parts[0]), let memory = Double(parts[1]), cpu.isFinite, memory.isFinite, cpu >= 0, memory >= 0 else {
                throw WidgetActionError(message: "Process list contained an invalid reading. Retrying with the next sample.")
            }
            return ProcessUsage(name: URL(fileURLWithPath: String(parts[2])).lastPathComponent, cpu: cpu, memory: memory)
        }.sorted { $0.cpu > $1.cpu }
    }
    func thermal() -> ThermalPressureState {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .unknown
        }
    }
}
