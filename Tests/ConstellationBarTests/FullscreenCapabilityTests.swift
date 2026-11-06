import AppKit
import XCTest
@testable import ConstellationBar

final class FullscreenCapabilityTests: XCTestCase {
    func testKnownSpacesAndUnavailableQueriesRemainDistinct() {
        let types: [UInt32: Int32] = [1: 0, 2: 2, 3: 4, 4: -1, 5: 999]
        var reads: [UInt32] = []
        let result = FullscreenDetector.snapshot([1,2,3,4,5,6,6]) { reads.append($0); return types[$0] }
        XCTAssertEqual(Set(reads), [1,2,3,4,5,6]); XCTAssertEqual(reads.count, 6)
        XCTAssertEqual(result.coveredDisplays, [3])
        XCTAssertEqual(result.unavailableDisplays, [4,5,6])
        XCTAssertEqual(result.diagnosticEntry().health, .attention)
        XCTAssertTrue(result.diagnosticEntry().detail.contains("3 of 6"))
    }

    func testDiagnosticsDistinguishesWaitingDisabledUnavailableAndRecoveredScopes() {
        let diagnostics = IntegrationDiagnostics()
        XCTAssertEqual(diagnostics.fullscreenEntry(requestedDisplays: [1]).health, .pending)
        XCTAssertEqual(diagnostics.fullscreenEntry(requestedDisplays: []).health, .disabled)
        diagnostics.fullscreen = FullscreenDetector.snapshot([1,2]) { _ in nil }
        XCTAssertEqual(diagnostics.fullscreenEntry(requestedDisplays: [1,2]).health, .attention)
        XCTAssertTrue(diagnostics.fullscreenEntry(requestedDisplays: [1,2]).detail.contains("bar stays visible"))
        XCTAssertEqual(diagnostics.fullscreenEntry(requestedDisplays: [1]).health, .pending, "A disconnected or newly scoped display must not reuse an old capability claim")
        diagnostics.fullscreen = FullscreenDetector.snapshot([1]) { _ in 0 }
        XCTAssertEqual(diagnostics.fullscreenEntry(requestedDisplays: [1]).health, .ready)
        XCTAssertEqual(diagnostics.fullscreenEntry(requestedDisplays: []).health, .disabled)
    }

    func testRepeatedVisibilitySamplesPublishOnlyChangesToTheirOwnDiagnostics() {
        let center = NotificationCenter()
        let first = IntegrationDiagnostics(notifications: center), second = IntegrationDiagnostics(notifications: center)
        let counter = ChangeCounter()
        let token = center.addObserver(forName: IntegrationDiagnostics.changed, object: first, queue: nil) { _ in counter.value += 1 }
        defer { center.removeObserver(token) }
        let failed = FullscreenDetector.snapshot([1]) { _ in nil }
        first.fullscreen = failed; first.fullscreen = failed
        XCTAssertEqual(counter.value, 1)
        first.fullscreen = FullscreenDetector.snapshot([1]) { _ in 0 }
        XCTAssertEqual(counter.value, 2); XCTAssertNil(second.fullscreen)
    }

    func testActualBarVisibilityUsesTheSameSnapshotAsDiagnosticsAndSkipsDisabledReads() throws {
        try requireGraphicalTests(); _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        var config = BarConfig.default; config.displayMode = .primaryOnly
        var activeType: Int32? = 4, reads = 0
        let diagnostics = IntegrationDiagnostics()
        let controller = ScreenBarController(config: config, readFullscreen: { ids in
            reads += 1
            XCTAssertEqual(Set(ids), [screen.displayID])
            return FullscreenDetector.snapshot(ids) { _ in activeType }
        })
        controller.onFullscreenChange = { diagnostics.fullscreen = $0 }
        let existing = Set(NSApp.windows.map(ObjectIdentifier.init))
        controller.installBars()
        defer { controller.closeBars() }
        let bar = try XCTUnwrap(NSApp.windows.compactMap { $0 as? BarWindow }.first { !existing.contains(ObjectIdentifier($0)) })
        XCTAssertFalse(bar.isVisible)
        XCTAssertEqual(diagnostics.fullscreen?.coveredDisplays, [screen.displayID])
        activeType = nil; controller.refreshVisibility()
        XCTAssertTrue(bar.isVisible)
        XCTAssertEqual(diagnostics.fullscreen?.unavailableDisplays, [screen.displayID])
        activeType = 0; controller.refreshVisibility()
        XCTAssertTrue(bar.isVisible)
        XCTAssertEqual(diagnostics.fullscreen?.diagnosticEntry().health, .ready)
        config.hideInFullscreen = false; controller.apply(config: config)
        let before = reads; controller.refreshVisibility()
        XCTAssertEqual(reads, before)
        XCTAssertEqual(diagnostics.fullscreen, .disabled); XCTAssertTrue(bar.isVisible)
        config.hideInFullscreen = true
        config.displayOverrides[screen.configurationID] = DisplayOverride(hideInFullscreen: false)
        controller.apply(config: config); controller.refreshVisibility()
        XCTAssertEqual(reads, before, "A per-display override disables detection even when the global option is on")
    }

    func testSettingsAndReportExposeTheSameFailureWithoutWritingTheClipboard() throws {
        try requireGraphicalTests(); _ = NSApplication.shared
        let diagnostics = IntegrationDiagnostics()
        let ids = NSScreen.screens.map(\.displayID)
        var config = BarConfig.default; config.displayMode = .allDisplays
        diagnostics.fullscreen = FullscreenDetector.snapshot(ids) { _ in nil }
        let controller = ConfigurationWindowController(config: config, diagnostics: diagnostics) { _ in }
        defer { controller.close() }
        XCTAssertEqual(controller.fullscreenDiagnosticRow?.status.stringValue, "Needs attention")
        XCTAssertTrue(controller.fullscreenDiagnosticRow?.detail.stringValue.contains("bar stays visible") == true)
        let report = controller.diagnosticReport()
        XCTAssertTrue(report.contains("Fullscreen visibility [Needs attention]"))
        XCTAssertTrue(report.contains("bar stays visible"))
        diagnostics.fullscreen = FullscreenDetector.snapshot(ids) { _ in 0 }
        XCTAssertEqual(controller.fullscreenDiagnosticRow?.status.stringValue, "Ready")
        XCTAssertTrue(controller.diagnosticReport().contains("Fullscreen visibility [Ready]"))
    }

    func testFullscreenHealthIsVisibleAndNavigatesToLayout() throws {
        try requireGraphicalTests(); _ = NSApplication.shared
        let controller = ConfigurationWindowController(config: .default) { _ in }
        defer { controller.close() }
        controller.selectSection(4)
        let content = try XCTUnwrap(controller.window?.contentView)
        let views = descendants(content)
        XCTAssertTrue(views.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "Fullscreen visibility" })
        let action = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.tag == -2 && $0.title == "Settings…" })
        _ = action.sendAction(try XCTUnwrap(action.action), to: action.target)
        XCTAssertEqual(controller.selectedSection, 0)
    }
    private func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
}

private final class ChangeCounter: @unchecked Sendable { var value = 0 }
