import AppKit
import XCTest
@testable import ConstellationBar

final class DailyWidgetPanelTests: XCTestCase {
    override func setUpWithError() throws { try super.setUpWithError(); try requireGraphicalTests(); _ = NSApplication.shared }
    private func buttons(_ view: NSView) -> [WidgetActionButton] { (view as? WidgetActionButton).map { [$0] } ?? view.subviews.flatMap(buttons) }
    func testDailyPanelsRenderAndRouteOnlyExplicitUserActions() throws {
        var state = SystemState()
        state.keyboard = KeyboardState(sources: [KeyboardSource(id: "en", name: "English", language: "en"), KeyboardSource(id: "jp", name: "Japanese", language: "ja")], selectedID: "en")
        var config = BarConfig.default; config.widgetPreferences.worldClockIdentifiers = ["Europe/London", "Asia/Tokyo"]
        for kind: WidgetKind in [.timer, .keepAwake, .reminders, .keyboard, .dateTime] {
            XCTAssertTrue(MiniAppPanel.kinds.contains(kind))
            let panel = MiniAppPanel(kind: kind, state: state, config: config, history: WidgetHistory())
            panel.frame.size = panel.preferredSize; panel.layoutSubtreeIfNeeded()
            var actions: [WidgetAction] = []
            panel.onAction = { action, completion in actions.append(action); completion(nil) }
            XCTAssertFalse(panel.stack.arrangedSubviews.isEmpty)
            XCTAssertTrue(actions.isEmpty, "Opening a panel must not change sleep, input source, or permission")
            switch kind {
            case .timer:
                let preset = try XCTUnwrap(buttons(panel).first { $0.title == "5 min" }); preset.performClick(nil)
                guard case .startTimer(seconds: 300) = actions.last else { return XCTFail("Timer preset must start a 5-minute countdown") }
            case .keepAwake:
                try XCTUnwrap(buttons(panel).first { $0.title == "15 min" }).performClick(nil)
                guard case .startKeepAwake(seconds: 900, display: false) = actions.last else { return XCTFail("Awake session must be bounded and leave display sleep enabled initially") }
            case .reminders:
                try XCTUnwrap(buttons(panel).first { $0.title == "Allow Reminders access…" }).performClick(nil)
                guard case .authorizeReminders = actions.last else { return XCTFail("Permission must require explicit action") }
            case .keyboard:
                try XCTUnwrap(buttons(panel).first { $0.title == "Japanese" }).performClick(nil)
                guard case .keyboardSource("jp") = actions.last else { return XCTFail("Input-source choice must route a keyboard action") }
            default: XCTAssertTrue(actions.isEmpty)
            }
        }
    }
    func testCountdownRefreshPreservesControlsAndCompletingRebuilds() {
        var state = SystemState(); state.timer = CountdownState(duration: 60, remaining: 60, running: true)
        let panel = MiniAppPanel(kind: .timer, state: state, config: .default, history: WidgetHistory())
        let countdown = panel.stack.arrangedSubviews.first as? NSTextField
        state.timer.remaining = 45; panel.update(state: state, history: WidgetHistory())
        XCTAssertTrue(panel.stack.arrangedSubviews.first === countdown)
        XCTAssertEqual(countdown?.stringValue, "0:45")
        state.timer = CountdownState(duration: 60, remaining: 0, running: false, finished: true)
        panel.update(state: state, history: WidgetHistory())
        XCTAssertFalse(panel.stack.arrangedSubviews.first === countdown)
        XCTAssertEqual((panel.stack.arrangedSubviews.first as? NSTextField)?.stringValue, "Time's up")
    }
}
