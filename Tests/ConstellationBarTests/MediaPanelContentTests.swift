import AppKit
import XCTest
@testable import ConstellationBar

final class MediaPanelContentTests: XCTestCase {
    override func setUpWithError() throws { try super.setUpWithError(); try requireGraphicalTests(); _ = NSApplication.shared }
    private func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
    private var sample: SystemState {
        var state = SystemState()
        state.mediaSessions = [
            MediaSession(id: "nativeMedia", providerID: "nativeMedia", playback: NowPlayingState(title: "First track", artist: "Fixture", isPlaying: true, source: "System", position: 10, duration: 180)),
            MediaSession(id: "appleMusic", providerID: "appleMusic", playback: NowPlayingState(title: "Second track", artist: "Fixture", isPlaying: false, source: "Apple Music", position: 20, duration: 200))
        ]
        return state
    }
    private func source(_ panel: MiniAppPanel) throws -> NSPopUpButton { try XCTUnwrap(descendants(panel).compactMap { $0 as? NSPopUpButton }.first) }
    private func button(_ title: String, in panel: MiniAppPanel) throws -> WidgetActionButton {
        try XCTUnwrap(descendants(panel).compactMap { $0 as? WidgetActionButton }.first { $0.title == title })
    }

    func testSourceAndTabSurviveRefreshAndActionsTargetTheSelectedSession() throws {
        var state = sample
        let panel = MiniAppPanel(kind: .nowPlaying, state: state, config: .default, history: WidgetHistory())
        let popup = try source(panel)
        XCTAssertEqual(popup.accessibilityLabel(), "Playback source")
        popup.selectItem(at: 1)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(popup.action), to: popup.target, from: popup))
        try button("Up next", in: panel).performClick(nil)
        state.mediaSessions[1].album = "New album" // Forces a structural rebuild.
        panel.update(state: state, history: WidgetHistory())
        XCTAssertEqual(try source(panel).indexOfSelectedItem, 1)
        XCTAssertEqual(try button("Up next", in: panel).state, .on)
        XCTAssertNoThrow(try button("View queue in Music", in: panel))
        var requestedSession: String?
        panel.onAction = { action, complete in
            if case let .playback(session, _) = action { requestedSession = session }
            complete(nil)
        }
        let play = try XCTUnwrap(descendants(panel).compactMap { $0 as? WidgetActionButton }.first { ["Play", "Pause"].contains($0.accessibilityLabel() ?? "") })
        play.performClick(nil)
        XCTAssertEqual(requestedSession, "appleMusic")
        state.mediaSessions[1].playback.position = 45
        panel.update(state: state, history: WidgetHistory())
        XCTAssertTrue(descendants(panel).compactMap { $0 as? NSTextField }.contains { $0.stringValue == "0:45" })
    }

    func testPanelSelectionsAreIndependentAndRemovedSourcesFallBackToAvailablePlayback() throws {
        var state = sample
        let first = MiniAppPanel(kind: .nowPlaying, state: state, config: .default, history: WidgetHistory())
        let second = MiniAppPanel(kind: .nowPlaying, state: state, config: .default, history: WidgetHistory())
        let popup = try source(first); popup.selectItem(at: 1)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(popup.action), to: popup.target, from: popup))
        XCTAssertEqual(try source(first).indexOfSelectedItem, 1)
        XCTAssertEqual(try source(second).indexOfSelectedItem, 0)
        state.mediaSessions.removeLast()
        first.update(state: state, history: WidgetHistory())
        XCTAssertTrue(descendants(first).compactMap { $0 as? NSTextField }.contains { $0.stringValue == "First track" })
        XCTAssertTrue(descendants(first).compactMap { $0 as? NSPopUpButton }.isEmpty)
    }

    func testFeatureContentAndRefreshClosuresDoNotRetainTheirHost() {
        weak var released: MiniAppPanel?
        autoreleasepool {
            let panel = MiniAppPanel(kind: .nowPlaying, state: sample, config: .default, history: WidgetHistory())
            released = panel
            panel.update(state: sample, history: WidgetHistory())
        }
        XCTAssertNil(released)
    }
}
