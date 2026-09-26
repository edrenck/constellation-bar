import AppKit
import XCTest

func requireGraphicalTests() throws {
    guard ProcessInfo.processInfo.environment["CONSTELLATION_UI_TESTS"] == "1" else {
        throw XCTSkip("Set CONSTELLATION_UI_TESTS=1 in a logged-in macOS session to run panel and window integration tests.")
    }
    guard NSScreen.main != nil else {
        if ProcessInfo.processInfo.environment["CONSTELLATION_REQUIRE_UI_TESTS"] == "1" {
            throw NSError(domain: "ConstellationUIJourney", code: 1, userInfo: [NSLocalizedDescriptionKey: "UI verification requires a logged-in macOS desktop. A build cannot pass this gate by skipping UI tests."])
        }
        throw XCTSkip("A graphical macOS session is required.")
    }
}
