import XCTest
@testable import ConstellationBar

final class WorkspaceReliabilityTests: XCTestCase {
    private let window = "42\tdev\tTerminal\tcom.apple.Terminal\tFixture\n"

    private final class Runner: CommandRunning {
        var results: [CommandResult]
        init(_ results: [CommandResult]) { self.results = results }
        func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> CommandResult {
            guard !results.isEmpty else { return CommandResult(error: "Unexpected command") }
            return results.removeFirst()
        }
    }

    private func client(_ results: [CommandResult]) -> AeroSpaceClient {
        AeroSpaceClient(binaryPath: "/usr/bin/true", runner: Runner(results))
    }

    func testEveryFollowupQueryRejectsFailedTimeoutAndTruncatedOutput() {
        let success = [CommandResult(output: "dev\t1\n", status: 0), CommandResult(output: "dev\n", status: 0),
                       CommandResult(output: window, status: 0), CommandResult(output: window, status: 0)]
        for index in 1...3 {
            for bad in [CommandResult(output: index == 1 ? "dev\n" : window, error: "Injected failure", status: 1),
                        CommandResult(output: index == 1 ? "dev\n" : window, status: 0, timedOut: true),
                        CommandResult(output: index == 1 ? "dev\n" : window, status: 0, outputTruncated: true)] {
                var results = success; results[index] = bad
                let snapshot = client(results).snapshot(config: .default)
                XCTAssertTrue(snapshot.isAvailable, "A failed detail query must preserve workspace availability")
                XCTAssertEqual(snapshot.workspaces.map(\.name), ["dev"])
                XCTAssertTrue(snapshot.status.contains("needs attention"))
                switch index {
                case 1: XCTAssertFalse(snapshot.workspaces.contains(where: \.isFocused))
                case 2: XCTAssertTrue(snapshot.workspaces.flatMap(\.windows).isEmpty)
                default: XCTAssertNil(snapshot.focusedWindow)
                }
            }
        }
        let snapshot = client(success).snapshot(config: .default)
        XCTAssertEqual(snapshot.status, "AeroSpace connected")
        XCTAssertEqual(snapshot.focusedWindow?.id, 42)
    }

    func testUnavailableSourceAndExpectedNoFocusedWindowAreDistinct() {
        for bad in [CommandResult(error: "Offline", status: 1), CommandResult(status: 0, timedOut: true), CommandResult(status: 0, outputTruncated: true)] {
            XCTAssertFalse(client([bad]).snapshot(config: .default).isAvailable)
        }
        let snapshot = client([CommandResult(output: "dev\t1\n", status: 0), CommandResult(output: "dev\n", status: 0),
                               CommandResult(status: 0), CommandResult(error: "No window is focused\n", status: 1)]).snapshot(config: .default)
        XCTAssertTrue(snapshot.isAvailable)
        XCTAssertEqual(snapshot.status, "AeroSpace connected")
        XCTAssertNil(snapshot.focusedWindow)
        XCTAssertTrue(snapshot.unavailableQueries.isEmpty)
    }

    func testMalformedWindowDataIsNotPresentedAsAnEmptyHealthyDesktop() {
        let snapshot = client([CommandResult(output: "dev\t1\n", status: 0), CommandResult(output: "dev\n", status: 0),
                               CommandResult(output: window + "incomplete\n", status: 0), CommandResult(output: "incomplete", status: 0)]).snapshot(config: .default)
        XCTAssertEqual(snapshot.unavailableQueries, [.windows, .focusedWindow])
        XCTAssertTrue(snapshot.status.contains("invalid data"))
        XCTAssertTrue(snapshot.workspaces.flatMap(\.windows).isEmpty)
    }

    func testPartialRefreshRetainsOnlyUnavailableFieldsAndDropsRemovedWorkspaces() {
        let oldWindow = AeroSpaceClient.parseWindow(window)!
        let previous = WorkspaceSnapshot(workspaces: [WorkspaceState(name: "dev", isFocused: true, windows: [oldWindow]),
                                                     WorkspaceState(name: "removed", isFocused: false, windows: [])], focusedWindow: oldWindow)
        let partial = WorkspaceSnapshot(workspaces: [WorkspaceState(name: "dev", isFocused: false, windows: []),
                                                    WorkspaceState(name: "new", isFocused: false, windows: [])],
                                        unavailableQueries: [.focusedWorkspace, .windows, .focusedWindow])
        let merged = partial.retainingUnavailableFields(from: previous)
        XCTAssertEqual(merged.workspaces.map(\.name), ["dev", "new"])
        XCTAssertEqual(merged.workspaces.first?.windows, [oldWindow])
        XCTAssertEqual(merged.workspaces.first?.isFocused, true)
        XCTAssertEqual(merged.focusedWindow, oldWindow)
        let emptySuccess = WorkspaceSnapshot(workspaces: [WorkspaceState(name: "dev", isFocused: true, windows: [])])
            .retainingUnavailableFields(from: previous)
        XCTAssertTrue(emptySuccess.workspaces[0].windows.isEmpty, "A successful empty result must clear stale windows")
        XCTAssertNil(emptySuccess.focusedWindow)
    }

    func testWorkspaceActionsReturnFailuresAndAllowRecovery() throws {
        let client = client([CommandResult(error: "Workspace missing", status: 1), CommandResult(status: 0, timedOut: true),
                             CommandResult(status: 0, outputTruncated: true), CommandResult(status: 0)])
        XCTAssertThrowsError(try client.switchToWorkspace("dev")) { XCTAssertTrue($0.localizedDescription.contains("Workspace missing")) }
        XCTAssertThrowsError(try client.focusWindow(42)) { XCTAssertTrue($0.localizedDescription.contains("timed out")) }
        XCTAssertThrowsError(try client.focusWindow(42)) { XCTAssertTrue($0.localizedDescription.contains("incomplete")) }
        XCTAssertNoThrow(try client.switchToWorkspace("dev"))
    }
}
