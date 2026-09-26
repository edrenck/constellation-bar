import XCTest
@testable import ConstellationBar

final class CommandRunnerTests: XCTestCase {
    func testCapturesOutputAndFailure() {
        let result = CommandRunner().run("/bin/sh", ["-c", "printf output; printf problem >&2; exit 7"], timeout: 1)
        XCTAssertEqual(result.output, "output")
        XCTAssertEqual(result.error, "problem")
        XCTAssertEqual(result.status, 7)
        XCTAssertFalse(result.succeeded)
    }
    func testLargeOutputDoesNotDeadlock() {
        let result = CommandRunner().run("/usr/bin/seq", ["1", "50000"], timeout: 3)
        XCTAssertTrue(result.succeeded)
        XCTAssertTrue(result.output.contains("50000"))
    }
    func testTimeoutTerminatesStalledCommand() {
        let start = Date()
        let result = CommandRunner().run("/bin/sleep", ["10"], timeout: 0.1)
        XCTAssertTrue(result.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }
    func testOverflowIsExplicitAndCannotBeParsedAsSuccess() {
        let result = CommandRunner().run("/usr/bin/seq", ["1", "250000"], timeout: 3)
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.outputTruncated)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.output.utf8.count, 1_048_576)
    }
    func testInheritedPipesDoNotLeaveReadersOrDescriptorsBehind() {
        let descriptorCount = { (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? 0 }
        let before = descriptorCount()
        let start = Date()
        for _ in 0..<5 {
            let result = CommandRunner().run("/bin/sh", ["-c", "sleep 2 & printf done; printf error >&2"], timeout: 1)
            XCTAssertEqual(result.output, "done")
            XCTAssertEqual(result.error, "error")
            XCTAssertTrue(result.outputTruncated)
            XCTAssertFalse(result.succeeded)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
        XCTAssertLessThanOrEqual(descriptorCount(), before + 2)
    }
    func testMissingCommandReturnsError() {
        let result = CommandRunner().run("/nonexistent/command", [], timeout: 1)
        XCTAssertFalse(result.succeeded)
        XCTAssertFalse(result.error.isEmpty)
    }
}
