import XCTest
@testable import ConstellationBar

final class FullscreenDetectorTests: XCTestCase {
    func testOnlyActiveNativeFullscreenDisplaysAreHidden() {
        // Desktop, fullscreen (Arc video or Split View), system, and unknown.
        let states: [UInt32: Int32] = [1: 0, 2: 4, 3: 2]
        XCTAssertEqual(FullscreenDetector.coveredDisplays([1, 2, 3, 4]) { states[$0] }, [2])
    }

    func testReturningToDesktopRestoresVisibility() {
        var activeType: Int32 = 4
        XCTAssertEqual(FullscreenDetector.coveredDisplays([1]) { _ in activeType }, [1])
        activeType = 0
        XCTAssertTrue(FullscreenDetector.coveredDisplays([1]) { _ in activeType }.isEmpty)
    }

    func testUnavailableNativeQueryKeepsBarsVisible() {
        XCTAssertTrue(FullscreenDetector.coveredDisplays([1, 2]) { _ in nil }.isEmpty)
    }
}
