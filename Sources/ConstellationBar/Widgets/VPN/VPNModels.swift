import Foundation
import AppKit


struct VPNConnection: Equatable {
    var name: String
    var connected: Bool
    var provider: String
    var id: String = ""
    var detail: String = "Routing details unavailable"
    var peers: [String] = []
    var canToggle = false
    var profileName: String = ""
    var protocolName: String = ""
    var serviceName: String {
        switch provider { case "tailscale": return "Tailscale"; case "surfshark": return "Surfshark"; default: return name }
    }
    var symbol: String { provider == "tailscale" ? "circle.grid.3x3.fill" : "lock.shield" }
}

struct VPNState: Equatable {
    var connections: [VPNConnection] = []
    var available = false
    var message = ""
    var tailwindConnected: Bool { connections.contains { $0.provider == "tailscale" && $0.connected } }
}

protocol VPNIntegrating: AnyObject {
    var id: String { get }
    func connections(config: BarConfig) -> VPNReadResult
}

struct VPNReadResult {
    enum Health: Equatable { case available, disabled, unavailable(String) }
    var connections: [VPNConnection] = []
    var health: Health
    var isAvailable: Bool { health == .available }
    var status: String {
        switch health {
        case .available: return "Available"
        case .disabled: return "Disabled"
        case let .unavailable(message): return message
        }
    }
}
