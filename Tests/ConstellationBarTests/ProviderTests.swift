import XCTest
@testable import ConstellationBar

final class ProviderTests: XCTestCase {
    func testWorkspaceDiscoveryDoesNotFilterNewOrNamedWorkspaces() {
        XCTAssertEqual(AeroSpaceClient.orderedNames(["10", "dev", "2", "chat", "dev"], preferred: ["dev", "absent"]), ["dev", "2", "10", "chat"])
    }
    func testMonitorParsingAndWindowTitles() {
        let spaces = AeroSpaceClient.parseWorkspaces("dev\t2\nchat\t1\n")
        XCTAssertEqual(spaces.first?.monitor, 2)
        let window = AeroSpaceClient.parseWindow("42\tdev\tTerminal\tcom.apple.Terminal\tA title\twith a tab\n")
        XCTAssertEqual(window?.title, "A title\twith a tab")
        XCTAssertNil(AeroSpaceClient.parseWindow("missing fields"))
    }
    func testVPNEnumeratesProvidersWithoutBrandAssumptions() {
        let connections = VPNProvider.parseServices("* (Connected) ABC PPP --> VPN \"Office WireGuard\" [VPN]\n* (Disconnected) DEF PPP --> VPN \"Personal\" [VPN]\n")
        XCTAssertEqual(connections.map(\.name), ["Office WireGuard", "Personal"])
        XCTAssertEqual(connections.map(\.connected), [true, false])
    }
    func testVPNPresentationUsesServiceIdentityAndRetainsProfileDetails() {
        var system = SystemState()
        system.vpn = VPNState(connections: [VPNConnection(name: "Tail", connected: true, provider: "tailscale")], available: true)
        let module = WidgetCatalog.module(for: .vpn)
        let single = module.presentation(system, .default, WidgetHistory())
        XCTAssertEqual(single.text, "Tailscale")
        XCTAssertEqual(single.icon, "circle.grid.3x3.fill")
        let profiles = VPNProvider.parseServices("* (Connected) 2794E9B3-B989-4DD0-AE93-0187C138B0AE VPN \"Surfshark. WireGuard®\" [VPN]\n")
        XCTAssertEqual(profiles.first?.profileName, "Surfshark. WireGuard®")
        XCTAssertEqual(profiles.first?.protocolName, "WireGuard")
        system.vpn.connections += profiles
        let multiple = module.presentation(system, .default, WidgetHistory())
        XCTAssertEqual(multiple.text, "2 connected")
        XCTAssertTrue(multiple.detail?.contains("Surfshark: Connected") == true)
        XCTAssertTrue(multiple.detail?.contains("Tailscale: Connected") == true)
    }
    func testTailscaleNamesPreferDNSAndFallBackToHostname() throws {
        let decoder = JSONDecoder()
        func name(_ json: String) throws -> String {
            try decoder.decode(TailscaleIntegration.PeerState.self, from: Data(json.utf8)).displayName
        }
        XCTAssertEqual(try name(#"{"HostName":"localhost","DNSName":"ipad.example.ts.net."}"#), "ipad")
        XCTAssertEqual(try name(#"{"HostName":"localhost","DNSName":"iphone-15-pro.example.ts.net."}"#), "iphone-15-pro")
        XCTAssertEqual(try name(#"{"HostName":"Desktop","DNSName":"siri.example.ts.net."}"#), "siri")
        XCTAssertEqual(try name(#"{"HostName":"build-server","DNSName":"  "}"#), "build-server")
        XCTAssertEqual(try name(#"{"HostName":"build-server"}"#), "build-server")
        XCTAssertEqual(try name(#"{"DNSName":"single-name"}"#), "single-name")
        XCTAssertEqual(try name(#"{}"#), "Unnamed device")
    }
    func testExplicitMissingExecutableDoesNotSilentlyUseAnother() {
        XCTAssertNil(ExecutableDiscovery.find("sh", override: "/nonexistent/explicit/path"))
        XCTAssertEqual(ExecutableDiscovery.find("sh", environment: ["PATH": "/bin"]), "/bin/sh")
    }
    func testDisabledProvidersAreNotSampled() {
        let battery = StubProvider(kinds: [.battery]), weather = StubProvider(kinds: [.weather])
        let monitor = SystemMonitor(providers: [battery, weather])
        var config = BarConfig.default
        config.rightWidgets = [.battery]
        _ = monitor.sample(config: config)
        XCTAssertEqual(battery.calls, 1)
        XCTAssertEqual(weather.calls, 0)
    }
    func testEveryWidgetHasPresentationAndInspector() {
        for kind in WidgetKind.allCases {
            let module = WidgetCatalog.module(for: kind)
            XCTAssertFalse(module.presentation(SystemState(), .default, WidgetHistory()).icon.isEmpty)
            XCTAssertFalse(module.rows(SystemState(), .default).isEmpty)
        }
    }
}
private final class StubProvider: SystemProviding {
    let kinds: Set<WidgetKind>
    var calls = 0
    init(kinds: Set<WidgetKind>) { self.kinds = kinds }
    func sample(config: BarConfig, into state: inout SystemState) { calls += 1 }
}
