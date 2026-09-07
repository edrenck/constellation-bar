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
}

struct CPUState: Equatable {
    var usage: Double
}

struct MemoryState: Equatable {
    var activeBytes: UInt64 = 0
    var wiredBytes: UInt64 = 0
    var compressedBytes: UInt64 = 0
    var usage: Double
    var usedBytes: UInt64 = 0
    var totalBytes: UInt64 = 0
}

struct DiskState: Equatable {
    var usage: Double
    var freeBytes: UInt64 = 0
    var totalBytes: UInt64 = 0
}

enum ThermalPressureState: String, Equatable {
    case nominal
    case fair
    case serious
    case critical

    var label: String {
        switch self {
        case .nominal: return "Cool"
        case .fair: return "Warm"
        case .serious: return "Hot"
        case .critical: return "Critical"
        }
    }
}
