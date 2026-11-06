import Foundation
import AppKit


struct ProcessUsage: Equatable {
    var name: String
    var cpu: Double
    var memory: Double
}

struct NetworkSpeedState: Equatable {
    var downloadBytesPerSecond: UInt64
    var uploadBytesPerSecond: UInt64
    var status: ReadingStatus = .available
    var interfaceNames: [String] = []
}

struct CPUState: Equatable {
    typealias Status = ReadingStatus
    var usage: Double
    var status: Status = .available
    var isAvailable: Bool { status == .available }
    var valueText: String { isAvailable ? "\(Int(usage.rounded()))%" : "—" }
    var statusDescription: String {
        switch status {
        case .available: return "CPU usage"
        case .waiting: return "Collecting CPU samples. The next reading establishes current usage."
        case let .failed(message): return message
        }
    }
}

struct MemoryState: Equatable {
    var activeBytes: UInt64 = 0
    var wiredBytes: UInt64 = 0
    var compressedBytes: UInt64 = 0
    var usage: Double
    var usedBytes: UInt64 = 0
    var totalBytes: UInt64 = 0
    var status: ReadingStatus = .available
    var valueText: String { status.isAvailable ? "\(Int(usage.rounded()))%" : "—" }
}

struct DiskState: Equatable {
    var usage: Double
    var freeBytes: UInt64 = 0
    var totalBytes: UInt64 = 0
    var status: ReadingStatus = .available
    var valueText: String { status.isAvailable ? "\(Int(usage.rounded()))%" : "—" }
}

enum ThermalPressureState: String, Equatable {
    case unknown
    case nominal
    case fair
    case serious
    case critical

    var label: String {
        switch self {
        case .unknown: return "Unavailable"
        case .nominal: return "Cool"
        case .fair: return "Warm"
        case .serious: return "Hot"
        case .critical: return "Critical"
        }
    }
}
