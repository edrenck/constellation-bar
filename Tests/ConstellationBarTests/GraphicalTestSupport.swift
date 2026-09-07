import AppKit
import XCTest

func requireGraphicalTests() throws {
    guard ProcessInfo.processInfo.environment["CONSTELLATION_UI_TESTS"] == "1" else {
        throw XCTSkip("Set CONSTELLATION_UI_TESTS=1 in a logged-in macOS session to run panel and window integration tests.")
    }
    guard NSScreen.main != nil else { throw XCTSkip("A graphical macOS session is required.") }
}
