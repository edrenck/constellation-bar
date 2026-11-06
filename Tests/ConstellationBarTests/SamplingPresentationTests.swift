import AppKit
import XCTest
@testable import ConstellationBar

final class SamplingPresentationTests: XCTestCase {
    override func setUpWithError() throws { try super.setUpWithError(); try requireGraphicalTests(); _ = NSApplication.shared }
    private func fields(_ view: NSView) -> [NSTextField] { view.subviews.flatMap { ($0 as? NSTextField).map { [$0] } ?? fields($0) } }
    private func buttons(_ view: NSView) -> [WidgetActionButton] { view.subviews.flatMap { ($0 as? WidgetActionButton).map { [$0] } ?? buttons($0) } }

    func testCPUUnavailableIsVisibleAndNeverAddsInventedHistory() {
        var date = Date(timeIntervalSince1970: 1000)
        let strip = WidgetStripView(frame: NSRect(x: 0, y: 0, width: 400, height: 46), now: { date })
        var config = BarConfig.default; config.systemUpdateInterval = 1; config.widgetPreferences.systemMetrics = [.cpu]
        config.setWidgetLayout(WidgetZoneLayout(left: [], center: [], right: [.widget(.system)]))
        strip.configure(kinds: [.system], theme: config.theme, visuals: config.visualPreferences)
        var state = SystemState()
        for cpu in [CPUState(usage: 0, status: .waiting), CPUState(usage: 0, status: .failed("Fixture CPU read failed")), CPUState(usage: 42), CPUState(usage: 0, status: .failed("Fixture CPU read failed")), CPUState(usage: 60)] {
            state.cpu = cpu; strip.update(system: state, config: config); date += 2
        }
        XCTAssertEqual(strip.fullHistory.cpu, [42, 60])
        XCTAssertEqual(strip.fullHistory.cpuDates, [Date(timeIntervalSince1970: 1004), Date(timeIntervalSince1970: 1008)])
        XCTAssertEqual(strip.fullHistory.dates.count, 5)
        state.cpu = CPUState(usage: 0, status: .failed("Fixture CPU read failed"))
        let presentation = WidgetCatalog.module(for: .system).presentation(state, config, strip.fullHistory)
        XCTAssertEqual(presentation.text, "CPU unavailable"); XCTAssertTrue(presentation.history.isEmpty)
        XCTAssertEqual(presentation.detail, "Fixture CPU read failed")
        let entries = IntegrationDiagnostics.entries(config: config, state: state, sampledWidgets: [.system], displayScope: DisplayScope(config: config, connectedDisplayIDs: ["fixture"]))
        XCTAssertEqual(entries.first { $0.widget == .system }?.health, .attention)
    }

    func testNativePanelsShowReadFailuresWithRecoveryInsteadOfZeroOrMissingDevices() throws {
        let message = "macOS could not read this sample. The next refresh retries automatically. Open system settings if the problem persists."
        for kind in [WidgetKind.system, .vpn] {
            var state = SystemState(); state.cpu = CPUState(usage: 0, status: .failed(message)); state.vpn = VPNState(message: message)
            let panel = MiniAppPanel(kind: kind, state: state, config: .default, history: WidgetHistory())
            let window = BarFloatingPanel(contentRect: NSRect(x: -10000, y: -10000, width: 320, height: 320))
            window.isReleasedWhenClosed = false; window.contentView = panel
            defer { window.close() }
            panel.layoutSubtreeIfNeeded()
            let feedback = try XCTUnwrap(fields(panel).first { $0.stringValue == message })
            XCTAssertGreaterThan(feedback.frame.height, 18)
            XCTAssertFalse(fields(panel).contains { $0.stringValue == "0%" || $0.stringValue.hasPrefix("No VPN services found") })
            if kind == .system {
                let sort = try XCTUnwrap(buttons(panel).first { $0.title == "CPU ↓" })
                XCTAssertGreaterThanOrEqual(sort.textContentRect.width, (sort.title as NSString).size(withAttributes: [.font: sort.font!]).width)
            }
        }
    }
}
