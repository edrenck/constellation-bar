import AppKit
import XCTest
@testable import ConstellationBar

final class MeasurementPresentationTests: XCTestCase {
    override func setUpWithError() throws { try super.setUpWithError(); try requireGraphicalTests(); _ = NSApplication.shared }
    private func fields(_ view: NSView) -> [NSTextField] { view.subviews.flatMap { ($0 as? NSTextField).map { [$0] } ?? fields($0) } }
    private func buttons(_ view: NSView) -> [WidgetActionButton] { view.subviews.flatMap { ($0 as? WidgetActionButton).map { [$0] } ?? buttons($0) } }
    private func sliders(_ view: NSView) -> [WidgetSlider] { view.subviews.flatMap { ($0 as? WidgetSlider).map { [$0] } ?? sliders($0) } }

    func testUnavailableMeasurementsReachViewsAndDiagnosticsWithoutZeros() throws {
        let message = "Fixture measurement failed. The next refresh retries automatically."
        var state = SystemState()
        state.cpu = CPUState(usage: 25); state.memory = MemoryState(usage: 0, status: .failed(message))
        state.network = NetworkSpeedState(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0, status: .failed(message)); state.disk = DiskState(usage: 0, status: .failed(message))
        var config = BarConfig.default; config.widgetPreferences.systemMetrics = [.memory, .network]
        config.setWidgetLayout(WidgetZoneLayout(left: [], center: [], right: [.widget(.system), .widget(.disk)]))
        let entries = IntegrationDiagnostics.entries(config: config, state: state, sampledWidgets: [.system, .disk], displayScope: DisplayScope(config: config, connectedDisplayIDs: ["fixture"]))
        XCTAssertEqual(entries.first { $0.widget == .system }?.health, .attention)
        XCTAssertEqual(entries.first { $0.widget == .disk }?.health, .attention)
        for kind in [WidgetKind.memory, .network, .disk] {
            let presentation = WidgetCatalog.module(for: kind).presentation(state, config, WidgetHistory())
            XCTAssertTrue(presentation.text.contains("unavailable")); XCTAssertTrue(presentation.history.isEmpty)
            XCTAssertEqual(WidgetCatalog.module(for: kind).rows(state, config).first?.1, message)
        }
        let panel = MiniAppPanel(kind: .memory, state: state, config: config, history: WidgetHistory())
        let window = BarFloatingPanel(contentRect: NSRect(x: -10000, y: -10000, width: 320, height: 360)); window.isReleasedWhenClosed = false; window.contentView = panel
        defer { window.close() }
        panel.layoutSubtreeIfNeeded()
        XCTAssertTrue(fields(panel).contains { $0.stringValue == message })
        XCTAssertFalse(fields(panel).contains { $0.stringValue == "0 B" || $0.stringValue == "0%" })
        let disk = WidgetInspectorView(kind: .disk, state: state, config: config, pinned: true)
        let diskWindow = BarFloatingPanel(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: disk.preferredSize)); diskWindow.isReleasedWhenClosed = false; diskWindow.contentView = disk
        defer { diskWindow.close() }
        disk.layoutSubtreeIfNeeded()
        let diskFeedback = try XCTUnwrap(fields(disk).first { $0.stringValue == message })
        XCTAssertGreaterThan(diskFeedback.frame.height, 18); XCTAssertEqual(diskFeedback.lineBreakMode, .byWordWrapping)
    }

    func testHistorySkipsFailedReadsAndDoesNotResampleCachedSnapshots() {
        var date = Date(timeIntervalSince1970: 1000)
        let strip = WidgetStripView(frame: NSRect(x: 0, y: 0, width: 400, height: 46), now: { date })
        let config = BarConfig.default
        var state = SystemState()
        for index in 0..<3 {
            state.metricsSampledAt = date
            state.memory = MemoryState(usage: Double(index+1)*10, status: index == 1 ? .failed("Failed") : .available)
            state.network = NetworkSpeedState(downloadBytesPerSecond: UInt64(index+1)*100, uploadBytesPerSecond: 0, status: index == 1 ? .failed("Failed") : .available)
            strip.update(system: state, config: config)
            date += 2
            strip.update(system: state, config: config) // Another provider republished the same metrics.
            date += 2
        }
        XCTAssertEqual(strip.fullHistory.memory, [10,30]); XCTAssertEqual(strip.fullHistory.network, [100,300])
        XCTAssertEqual(strip.fullHistory.memoryDates, [Date(timeIntervalSince1970: 1000), Date(timeIntervalSince1970: 1008)])
        XCTAssertEqual(strip.fullHistory.networkDates, strip.fullHistory.memoryDates)
        XCTAssertEqual(strip.fullHistory.dates.count, 3)
    }

    func testAudioUnknownControlsStayDisabledAndRecoverAfterRetry() throws {
        let hardware = FixtureAudioHardware(), provider = AudioProvider(hardware: hardware)
        hardware.failures[FixtureAudioHardware.volume()] = "Volume read failed"
        hardware.failures[FixtureAudioHardware.mute()] = "Mute read failed"
        var state = SystemState(); state.audio = provider.snapshot()
        let panel = MiniAppPanel(kind: .audio, state: state, config: .default, history: WidgetHistory())
        let window = BarFloatingPanel(contentRect: NSRect(x: -10000, y: -10000, width: 320, height: 380)); window.isReleasedWhenClosed = false; window.contentView = panel
        defer { window.close() }
        panel.layoutSubtreeIfNeeded()
        XCTAssertTrue(try XCTUnwrap(sliders(panel).first).isHidden)
        let unknownMute = try XCTUnwrap(buttons(panel).first { $0.accessibilityLabel() == "Mute status unavailable" })
        XCTAssertFalse(unknownMute.isEnabled); XCTAssertEqual(unknownMute.state, .mixed)
        var retried = false
        panel.onAction = { [weak panel] action, complete in
            if case .refreshAudio = action { retried = true } else { XCTFail("Expected Audio refresh") }
            hardware.failures = [:]; state.audio = provider.snapshot(); complete(nil); panel?.update(state: state, history: WidgetHistory())
        }
        try XCTUnwrap(buttons(panel).first { $0.title == "Retry" }).performClick(nil)
        panel.layoutSubtreeIfNeeded()
        XCTAssertTrue(retried); XCTAssertFalse(try XCTUnwrap(sliders(panel).first).isHidden)
        XCTAssertTrue(try XCTUnwrap(sliders(panel).first).isEnabled)
        XCTAssertFalse(fields(panel).contains { $0.stringValue.contains("Volume read failed") })
    }

    func testEmptyAudioAndVPNStatesKeepDirectRecoveryControlsReachable() throws {
        for kind in [WidgetKind.audio, .vpn] {
            var state = SystemState(); state.audio = AudioState(status: .failed("Audio unavailable. Retry or open Sound settings.")); state.vpn = VPNState(message: "VPN unavailable. Retry or open VPN settings.")
            let panel = MiniAppPanel(kind: kind, state: state, config: .default, history: WidgetHistory())
            let window = BarFloatingPanel(contentRect: NSRect(x: -10000, y: -10000, width: 320, height: 300)); window.isReleasedWhenClosed = false; window.contentView = panel
            defer { window.close() }
            panel.layoutSubtreeIfNeeded()
            var retried = false
            panel.onAction = { action, complete in XCTAssertEqual(action.providerKind, kind); retried = true; complete(nil) }
            try XCTUnwrap(buttons(panel).first { $0.title == "Retry" }).performClick(nil)
            panel.layoutSubtreeIfNeeded()
            XCTAssertTrue(retried)
            let settings = try XCTUnwrap(buttons(panel).first { $0.title == (kind == .audio ? "Sound settings…" : "VPN settings…") })
            settings.scrollToVisible(settings.bounds)
            XCTAssertTrue(panel.scroll.documentVisibleRect.insetBy(dx: -1, dy: -1).contains(settings.convert(settings.bounds, to: panel.document)))
        }
    }
}
