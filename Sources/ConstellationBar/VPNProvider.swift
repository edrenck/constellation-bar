import Foundation

final class VPNProvider: SystemProviding {
    let kinds: Set<WidgetKind> = [.vpn]
    private let integrations: [VPNIntegrating]
    init(runner: CommandRunning = CommandRunner()) {
        integrations = [SystemVPNIntegration(runner: runner), TailscaleIntegration(runner: runner)]
    }
    func sample(config: BarConfig, into state: inout SystemState) {
        var connections: [VPNConnection] = []
        for integration in integrations {
            let result = integration.connections(config: config)
            if integration.id == "tailscale", !result.connections.isEmpty { connections.removeAll { $0.provider == "tailscale" } }
            connections += result.connections
            state.providerStatuses.append(ProviderStatus(id: integration.id, message: result.status))
        }
        state.vpn = VPNState(connections: connections, available: !connections.isEmpty || state.providerStatuses.contains { $0.id == "systemVPN" && $0.message == "Available" })
    }
    static func parseServices(_ output: String) -> [VPNConnection] { SystemVPNIntegration.parseServices(output) }
}
final class SystemVPNIntegration: VPNIntegrating {
    let id = "systemVPN"
    private let runner: CommandRunning
    init(runner: CommandRunning = CommandRunner()) { self.runner = runner }
    func connections(config: BarConfig) -> (connections: [VPNConnection], status: String) {
        let result = runner.run("/usr/sbin/scutil", ["--nc", "list"], timeout: 1)
        let connections = Self.parseServices(result.output).filter { config.providerPreferences.includes($0.provider == "system" ? "systemVPN" : $0.provider) }.map { connection -> VPNConnection in
            var value = connection
            if value.provider == "surfshark" { value.name = config.surfsharkDisplayName + " · " + String(value.id.prefix(6)); value.detail = "macOS reports this profile as " + (connection.connected ? "connected." : "disconnected.") + " Server location, public IP and protection settings are not exposed by this adapter. Open Surfshark for those details." }
            if value.provider == "tailscale" { value.name = config.tailwindDisplayName }
            return value
        }
        return (connections, result.succeeded ? "Available" : "macOS VPN status unavailable")
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
    static func setConnected(_ connected: Bool, service: String) throws {
        let runner = CommandRunner()
        guard UUID(uuidString: service) != nil, parseServices(runner.run("/usr/sbin/scutil", ["--nc", "list"], timeout: 1).output).contains(where: { $0.id == service && $0.canToggle }) else { throw WidgetActionError(message: "That VPN service is no longer available for control.") }
        let result = runner.run("/usr/sbin/scutil", ["--nc", connected ? "start" : "stop", service], timeout: 5)
        guard result.succeeded else { throw WidgetActionError(message: "macOS could not change the VPN connection. Open VPN settings to check its configuration.") }
    }
}
final class TailscaleIntegration: VPNIntegrating {
    let id = "tailscale"
    private let runner: CommandRunning
    init(runner: CommandRunning = CommandRunner()) { self.runner = runner }
    func connections(config: BarConfig) -> (connections: [VPNConnection], status: String) {
        guard config.providerPreferences.includes(id) else { return ([], "Disabled") }
        guard let path = ExecutableDiscovery.find("tailscale") else { return ([], "Install the Tailscale CLI for peer and routing details.") }
        let result = runner.run(path, ["status", "--json"], timeout: 1)
        guard result.succeeded, let data = result.output.data(using: .utf8), let status = try? JSONDecoder().decode(Status.self, from: data) else { return ([], "Tailscale CLI unavailable") }
        let peers = (status.Peer ?? [:]).sorted {
            let order = $0.value.displayName.localizedStandardCompare($1.value.displayName)
            return order == .orderedSame ? $0.key < $1.key : order == .orderedAscending
        }.map { "\($0.value.displayName) · \($0.value.Online == true ? "Online" : "Offline")" }
        let detail: String
        if let exit = status.ExitNodeStatus { detail = "Mesh network · exit node \(exit.Online == true ? "online" : "unavailable")" }
        else { detail = "Mesh network · exit node off" }
        return ([VPNConnection(name: config.tailwindDisplayName, connected: status.BackendState == "Running", provider: id, id: "tailscale", detail: detail, peers: peers)], "Available")
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
