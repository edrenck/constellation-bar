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
        case .cpu: return "\(Int(state.cpu.usage.rounded()))%"
        case .memory: return "\(Int(state.memory.usage.rounded()))%"
        case .network: return ByteFormatter.compactSpeed(state.network.downloadBytesPerSecond)
        case .thermal: return state.thermal.label
        }
    }
    func summary(_ state: SystemState) -> String {
        switch self {
        case .cpu: return "CPU \(Int(state.cpu.usage.rounded()))%"
        case .memory: return "RAM \(Int(state.memory.usage.rounded()))%"
        case .network: return "↓\(ByteFormatter.compactSpeed(state.network.downloadBytesPerSecond))"
        case .thermal: return state.thermal.label
        }
    }
}
