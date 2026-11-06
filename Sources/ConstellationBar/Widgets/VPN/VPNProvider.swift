import Foundation

final class VPNProvider: SystemProviding {
    let kinds: Set<WidgetKind> = [.vpn]
    private let integrations: [VPNIntegrating]
    private let system: SystemVPNIntegration
    init(runner: CommandRunning = CommandRunner()) {
        system = SystemVPNIntegration(runner: runner)
        integrations = [system, TailscaleIntegration(runner: runner)]
    }
    func sample(config: BarConfig, into state: inout SystemState) {
        var connections: [VPNConnection] = []
        var available = false
        var messages: [String] = []
        let ids = Set(integrations.map(\.id))
        state.providerStatuses.removeAll { ids.contains($0.id) }
        for integration in integrations {
            let result = integration.connections(config: config)
            available = available || result.isAvailable
            if case let .unavailable(message) = result.health { messages.append(message) }
            if integration.id == "tailscale", !result.connections.isEmpty { connections.removeAll { $0.provider == "tailscale" } }
            connections += result.connections
            state.providerStatuses.append(ProviderStatus(id: integration.id, message: result.status, needsAttention: result.health != .disabled && !result.isAvailable))
        }
        state.vpn = VPNState(connections: connections, available: available, message: messages.joined(separator: "\n"))
    }
    static func parseServices(_ output: String) -> [VPNConnection] { SystemVPNIntegration.parseServices(output) }
    func setConnected(_ connected: Bool, service: String) throws { try system.setConnected(connected, service: service) }
}
final class SystemVPNIntegration: VPNIntegrating {
    let id = "systemVPN"
    private let runner: CommandRunning
    init(runner: CommandRunning = CommandRunner()) { self.runner = runner }
    func connections(config: BarConfig) -> VPNReadResult {
        guard config.providerPreferences.includes(id) else { return VPNReadResult(health: .disabled) }
        let result = runner.run("/usr/sbin/scutil", ["--nc", "list"], timeout: 1)
        guard result.succeeded else { return VPNReadResult(health: .unavailable(Self.failureMessage(result))) }
        let connections = Self.parseServices(result.output).filter { config.providerPreferences.includes($0.provider == "system" ? "systemVPN" : $0.provider) }.map { connection -> VPNConnection in
            var value = connection
            if value.provider == "surfshark" { value.name = config.surfsharkDisplayName + " · " + String(value.id.prefix(6)); value.detail = "macOS reports this profile as " + (connection.connected ? "connected." : "disconnected.") + " Server location, public IP and protection settings are not exposed by this adapter. Open Surfshark for those details." }
            if value.provider == "tailscale" { value.name = config.tailwindDisplayName }
            return value
        }
        return VPNReadResult(connections: connections, health: .available)
    }
    static func parseServices(_ output: String) -> [VPNConnection] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            guard let first = line.firstIndex(of: "\""), let last = line.lastIndex(of: "\""), first < last else { return nil }
            let name = String(line[line.index(after: first)..<last])
            let provider = name.localizedCaseInsensitiveContains("tailscale") ? "tailscale" : name.localizedCaseInsensitiveContains("surfshark") ? "surfshark" : "system"
            let uuid = line.split(whereSeparator: \.isWhitespace).first { UUID(uuidString: String($0)) != nil }.map(String.init) ?? ""
            return VPNConnection(name: name, connected: line.contains("(Connected)"), provider: provider, id: uuid, detail: provider == "tailscale" ? "Mesh network · routing details unavailable" : "VPN service · routing details unavailable", canToggle: provider == "system" && !uuid.isEmpty, profileName: name, protocolName: name.localizedCaseInsensitiveContains("wireguard") ? "WireGuard" : name.localizedCaseInsensitiveContains("ikev2") ? "IKEv2" : name.localizedCaseInsensitiveContains("openvpn") ? "OpenVPN" : "")
        }
    }
    func setConnected(_ connected: Bool, service: String) throws {
        guard UUID(uuidString: service) != nil else { throw WidgetActionError(message: "That VPN service is no longer available for control.") }
        let listing = runner.run("/usr/sbin/scutil", ["--nc", "list"], timeout: 1)
        guard listing.succeeded else { throw WidgetActionError(message: Self.failureMessage(listing)) }
        guard Self.parseServices(listing.output).contains(where: { $0.id == service && $0.canToggle }) else { throw WidgetActionError(message: "That VPN service is no longer available for control.") }
        let result = runner.run("/usr/sbin/scutil", ["--nc", connected ? "start" : "stop", service], timeout: 5)
        guard result.succeeded else { throw WidgetActionError(message: "macOS could not change the VPN connection. Open VPN settings to check its configuration.") }
    }
    private static func failureMessage(_ result: CommandResult) -> String {
        let reason = result.timedOut ? "timed out" : result.outputTruncated ? "returned incomplete output" : "failed (exit \(result.status))"
        return "macOS VPN status \(reason). Retry or open VPN settings."
    }
}
final class TailscaleIntegration: VPNIntegrating {
    let id = "tailscale"
    private let runner: CommandRunning
    init(runner: CommandRunning = CommandRunner()) { self.runner = runner }
    func connections(config: BarConfig) -> VPNReadResult {
        guard config.providerPreferences.includes(id) else { return VPNReadResult(health: .disabled) }
        guard let path = ExecutableDiscovery.find("tailscale") else { return VPNReadResult(health: .unavailable("Install the Tailscale CLI for peer and routing details.")) }
        let result = runner.run(path, ["status", "--json"], timeout: 1)
        guard result.succeeded, let data = result.output.data(using: .utf8), let status = try? JSONDecoder().decode(Status.self, from: data) else { return VPNReadResult(health: .unavailable("Tailscale CLI unavailable")) }
        let peers = (status.Peer ?? [:]).sorted {
            let order = $0.value.displayName.localizedStandardCompare($1.value.displayName)
            return order == .orderedSame ? $0.key < $1.key : order == .orderedAscending
        }.map { "\($0.value.displayName) · \($0.value.Online == true ? "Online" : "Offline")" }
        let detail: String
        if let exit = status.ExitNodeStatus { detail = "Mesh network · exit node \(exit.Online == true ? "online" : "unavailable")" }
        else { detail = "Mesh network · exit node off" }
        return VPNReadResult(connections: [VPNConnection(name: config.tailwindDisplayName, connected: status.BackendState == "Running", provider: id, id: "tailscale", detail: detail, peers: peers)], health: .available)
    }
    private struct Status: Decodable {
        var BackendState: String
        var Peer: [String: PeerState]?
        var ExitNodeStatus: ExitState?
    }
    struct PeerState: Decodable {
        var HostName: String?
        var DNSName: String?
        var Online: Bool?
        var displayName: String {
            let dns = (DNSName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let name = dns.split(separator: ".", omittingEmptySubsequences: false).first, !name.isEmpty { return String(name) }
            let host = (HostName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return host.isEmpty ? "Unnamed device" : host
        }
    }
    private struct ExitState: Decodable { var Online: Bool? }
}
