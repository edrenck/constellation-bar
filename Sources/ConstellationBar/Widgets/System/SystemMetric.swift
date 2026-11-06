import Foundation

enum SystemMetric: String, Codable, CaseIterable {
    case cpu, memory, network, thermal
    var title: String {
        switch self { case .cpu: return "CPU"; case .memory: return "Memory"; case .network: return "Network"; case .thermal: return "Thermal Pressure" }
    }
    var legacyWidget: WidgetKind {
        switch self { case .cpu: return .cpu; case .memory: return .memory; case .network: return .network; case .thermal: return .thermal }
    }
    func compactSummary(_ state: SystemState) -> String {
        switch self {
        case .cpu: return state.cpu.valueText
        case .memory: return state.memory.valueText
        case .network: return state.network.status.isAvailable ? ByteFormatter.compactSpeed(state.network.downloadBytesPerSecond) : "—"
        case .thermal: return state.thermal.label
        }
    }
    func summary(_ state: SystemState) -> String {
        switch self {
        case .cpu: return state.cpu.isAvailable ? "CPU \(state.cpu.valueText)" : "CPU unavailable"
        case .memory: return state.memory.status.isAvailable ? "RAM \(state.memory.valueText)" : "Memory unavailable"
        case .network: return state.network.status.isAvailable ? "↓\(ByteFormatter.compactSpeed(state.network.downloadBytesPerSecond))" : "Network unavailable"
        case .thermal: return state.thermal.label
        }
    }
    func status(_ state: SystemState) -> ReadingStatus {
        switch self {
        case .cpu: return state.cpu.status
        case .memory: return state.memory.status
        case .network: return state.network.status
        case .thermal: return state.thermal == .unknown ? .failed("macOS did not supply a thermal reading.") : .available
        }
    }
}
