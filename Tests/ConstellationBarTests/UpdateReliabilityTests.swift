import XCTest
import Foundation
import CryptoKit
@testable import ConstellationBar

final class UpdateTransferTests: XCTestCase {
    private func configuration(status: Int = 200, length: Int? = nil, chunks: [Data], delay: TimeInterval = 0) -> URLSessionConfiguration {
        TransferURLProtocol.configure(status: status, length: length, chunks: chunks, delay: delay)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TransferURLProtocol.self]
        return configuration
    }

    func testRejectsDeclaredLengthBeforeAcceptingBodyAndDeletesFile() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let transfer = UpdateTransfer(configuration: configuration(length: 1000, chunks: [Data("small".utf8)]), limit: 10, destination: file)
        do { _ = try await transfer.receive(URLRequest(url: URL(string: "https://example.test/archive")!)); XCTFail("Oversized header accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("declared")) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testCountsMissingAndFalseContentLengthsWhileStreaming() async {
        for length in [nil, 1] as [Int?] {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let transfer = UpdateTransfer(configuration: configuration(length: length, chunks: [Data(repeating: 1, count: 6), Data(repeating: 2, count: 6)]), limit: 10, destination: file)
            do { _ = try await transfer.receive(URLRequest(url: URL(string: "https://example.test/archive")!)); XCTFail("Oversized stream accepted") }
            catch { XCTAssertTrue(error.localizedDescription.contains("large"), error.localizedDescription) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        }
    }

    func testMetadataBoundAndHTTPFailure() async {
        let request = URLRequest(url: URL(string: "https://example.test/metadata")!)
        for (status, chunks) in [(503, [Data("failure".utf8)]), (200, [Data(repeating: 1, count: 11)])] {
            let transfer = UpdateTransfer(configuration: configuration(status: status, chunks: chunks), limit: 10)
            do { _ = try await transfer.receive(request); XCTFail("Invalid response accepted") }
            catch { XCTAssertTrue(error.localizedDescription.contains(status == 503 ? "HTTP 503" : "large")) }
        }
    }

    func testCancellationCleansTemporaryFile() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let transfer = UpdateTransfer(configuration: configuration(chunks: [Data("body".utf8)], delay: 0.2), limit: 10, destination: file)
        let task = Task { try await transfer.receive(URLRequest(url: URL(string: "https://example.test/archive")!)) }
        try await Task.sleep(nanoseconds: 20_000_000)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled transfer succeeded") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testValidDownloadRetainedAndHasIncrementalChecksum() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let body = Data(repeating: 42, count: 200_000)
        let chunks = stride(from: 0, to: body.count, by: 8192).map { body.subdata(in: $0..<min($0 + 8192, body.count)) }
        let transfer = UpdateTransfer(configuration: configuration(length: body.count, chunks: chunks), limit: body.count, destination: file)
        let metadata = try await transfer.receive(URLRequest(url: URL(string: "https://example.test/archive")!))
        XCTAssertTrue(metadata.isEmpty, "Archive bytes must remain on disk, not in metadata memory")
        XCTAssertEqual(try Data(contentsOf: file), body)
        XCTAssertEqual(try UpdateTransfer.sha256(of: file), SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined())
    }
}

private final class TransferURLProtocol: URLProtocol {
    private struct Fixture { var status: Int; var length: Int?; var chunks: [Data]; var delay: TimeInterval }
    private static let lock = NSLock()
    private static var fixture = Fixture(status: 200, length: nil, chunks: [], delay: 0)
    private var work: DispatchWorkItem?
    private let stateLock = NSLock()
    private var stopped = false
    static func configure(status: Int, length: Int?, chunks: [Data], delay: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        fixture = Fixture(status: status, length: length, chunks: chunks, delay: delay)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let fixture = Self.fixture; Self.lock.unlock()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.stateLock.lock(); let stopped = self.stopped; self.stateLock.unlock()
            guard !stopped else { return }
            let headers = fixture.length.map { ["Content-Length": String($0)] }
            self.client?.urlProtocol(self, didReceive: HTTPURLResponse(url: self.request.url!, statusCode: fixture.status, httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
            for chunk in fixture.chunks { self.client?.urlProtocol(self, didLoad: chunk) }
            self.client?.urlProtocolDidFinishLoading(self)
        }
        work = item
        DispatchQueue.global().asyncAfter(deadline: .now() + fixture.delay, execute: item)
    }
    override func stopLoading() { stateLock.lock(); stopped = true; stateLock.unlock(); work?.cancel() }
}

final class UpdateTransactionTests: XCTestCase {
    private final class Fixture {
        let root: URL
        let receipt: UpdateReceipt
        var moveCount = 0
        var failMove: Int?
        var failLaunch = false
        var acknowledge = false
        var wrongAcknowledgment = false
        var stopSucceeds = true
        var stopped: [Int32] = []
        var launched: [(URL, [String])] = []
        var clock: TimeInterval = 0
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let directory = root.appendingPathComponent(".ConstellationBar-update-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            receipt = UpdateReceipt(token: UUID().uuidString, destination: root.appendingPathComponent("Installed.app"), stagedApp: directory.appendingPathComponent("ConstellationBar.app"), version: "v1.0.0", parentPID: 1)
            for (path, content) in [(receipt.destination, "old"), (receipt.stagedApp, "new")] {
                try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
                try Data(content.utf8).write(to: path.appendingPathComponent("identity"))
            }
            try Data("personal configuration".utf8).write(to: root.appendingPathComponent("configuration.json"))
            try receipt.save()
        }
        deinit { try? FileManager.default.removeItem(at: root) }
        var operations: UpdateTransaction.Operations {
            UpdateTransaction.Operations(move: { [self] source, target in
                moveCount += 1
                if failMove == moveCount { throw UpdateError(message: "injected move failure \(moveCount)") }
                try FileManager.default.moveItem(at: source, to: target)
            }, launch: { [self] app, arguments in
                launched.append((app, arguments))
                if failLaunch && launched.count == 1 { throw UpdateError(message: "injected launch failure") }
                if acknowledge && !arguments.isEmpty {
                    let ack = UpdateStartupAcknowledgment(token: wrongAcknowledgment ? "wrong" : receipt.token, pid: 42)
                    try JSONEncoder().encode(ack).write(to: receipt.acknowledgmentURL)
                }
                return 42
            }, terminate: { [self] pid in stopped.append(pid); return stopSucceeds }, sleep: { [self] duration in clock += duration }, now: { [self] in clock })
        }
        func identity(_ url: URL) -> String? { (try? Data(contentsOf: url.appendingPathComponent("identity"))).map { String(decoding: $0, as: UTF8.self) } }
        func assertConfigurationUntouched(file: StaticString = #filePath, line: UInt = #line) throws {
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("configuration.json")), "personal configuration", file: file, line: line)
        }
    }

    func testFirstAndSecondMoveFailuresRestoreSingleUsableApp() throws {
        for failMove in [1, 2] {
            let fixture = try Fixture()
            fixture.failMove = failMove
            var transaction = UpdateTransaction(receipt: fixture.receipt, operations: fixture.operations, acknowledgmentTimeout: 1)
            XCTAssertThrowsError(try transaction.run())
            XCTAssertEqual(fixture.identity(fixture.receipt.destination), "old")
            XCTAssertNil(fixture.identity(fixture.receipt.backup))
            XCTAssertNil(fixture.identity(fixture.receipt.stagedApp))
            XCTAssertEqual(try UpdateReceipt.load(fixture.receipt.receiptURL).state, .rolledBack)
            try fixture.assertConfigurationUntouched()
        }
    }

    func testLaunchFailureRollsBackAndRecordsError() throws {
        let fixture = try Fixture()
        fixture.failLaunch = true
        var transaction = UpdateTransaction(receipt: fixture.receipt, operations: fixture.operations, acknowledgmentTimeout: 1)
        XCTAssertThrowsError(try transaction.run())
        XCTAssertEqual(fixture.identity(fixture.receipt.destination), "old")
        XCTAssertNil(fixture.identity(fixture.receipt.failedApp))
        XCTAssertTrue(try UpdateReceipt.load(fixture.receipt.receiptURL).error!.contains("launch failure"))
        XCTAssertTrue(try String(contentsOf: fixture.receipt.directory.appendingPathComponent("installer.log")).contains("Previous app restored"))
        try fixture.assertConfigurationUntouched()
    }

    func testMissingAndWrongAcknowledgmentTerminateReplacementAndRestorePrevious() throws {
        for invalidAck in [false, true] {
            let fixture = try Fixture()
            fixture.acknowledge = invalidAck
            fixture.wrongAcknowledgment = invalidAck
            var transaction = UpdateTransaction(receipt: fixture.receipt, operations: fixture.operations, acknowledgmentTimeout: 1)
            XCTAssertThrowsError(try transaction.run())
            XCTAssertEqual(fixture.stopped, [42])
            XCTAssertEqual(fixture.identity(fixture.receipt.destination), "old")
            XCTAssertNil(fixture.identity(fixture.receipt.backup))
            XCTAssertNil(fixture.identity(fixture.receipt.failedApp))
            XCTAssertLessThan(fixture.clock, 1.2)
            try fixture.assertConfigurationUntouched()
        }
    }

    func testConfirmedStartupRemovesPreviousAppAndRetainsReceipt() throws {
        let fixture = try Fixture()
        fixture.acknowledge = true
        var transaction = UpdateTransaction(receipt: fixture.receipt, operations: fixture.operations, acknowledgmentTimeout: 1)
        try transaction.run()
        XCTAssertEqual(fixture.identity(fixture.receipt.destination), "new")
        XCTAssertNil(fixture.identity(fixture.receipt.backup))
        XCTAssertEqual(try UpdateReceipt.load(fixture.receipt.receiptURL).state, .succeeded)
        XCTAssertEqual(fixture.stopped, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.receipt.acknowledgmentURL.path))
        try fixture.assertConfigurationUntouched()
    }

    func testUnstoppableReplacementPreservesBackupAndRecoveryReceipt() throws {
        let fixture = try Fixture()
        fixture.stopSucceeds = false
        var transaction = UpdateTransaction(receipt: fixture.receipt, operations: fixture.operations, acknowledgmentTimeout: 1)
        XCTAssertThrowsError(try transaction.run())
        XCTAssertEqual(fixture.identity(fixture.receipt.backup), "old")
        XCTAssertEqual(fixture.identity(fixture.receipt.destination), "new")
        XCTAssertEqual(try UpdateReceipt.load(fixture.receipt.receiptURL).state, .recoveryRequired)
        try fixture.assertConfigurationUntouched()
    }

    func testRollbackMoveFailureRetainsPreviousAppForExplicitRecovery() throws {
        let fixture = try Fixture()
        fixture.failMove = 3
        var transaction = UpdateTransaction(receipt: fixture.receipt, operations: fixture.operations, acknowledgmentTimeout: 1)
        XCTAssertThrowsError(try transaction.run())
        XCTAssertEqual(fixture.identity(fixture.receipt.backup), "old")
        XCTAssertEqual(fixture.identity(fixture.receipt.destination), "new")
        XCTAssertEqual(try UpdateReceipt.load(fixture.receipt.receiptURL).state, .recoveryRequired)
        try fixture.assertConfigurationUntouched()
    }

    func testBackupCleanupFailureNeverRollsBackConfirmedUpdate() throws {
        let fixture = try Fixture()
        fixture.acknowledge = true
        var operations = fixture.operations
        operations.remove = { _ in throw UpdateError(message: "injected cleanup failure") }
        var transaction = UpdateTransaction(receipt: fixture.receipt, operations: operations, acknowledgmentTimeout: 1)
        try transaction.run()
        XCTAssertEqual(fixture.identity(fixture.receipt.destination), "new")
        XCTAssertEqual(fixture.identity(fixture.receipt.backup), "old")
        let receipt = try UpdateReceipt.load(fixture.receipt.receiptURL)
        XCTAssertEqual(receipt.state, .succeeded)
        XCTAssertTrue(receipt.error!.contains("cleanup failed"))
        XCTAssertEqual(fixture.stopped, [])
    }

    func testPruningRetainsFiveReceiptsAndNeverDeletesPendingBackups() throws {
        let fixture = try Fixture()
        var completed: [URL] = []
        for _ in 0..<7 {
            let directory = fixture.root.appendingPathComponent(".ConstellationBar-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            var receipt = UpdateReceipt(token: UUID().uuidString, destination: fixture.receipt.destination, stagedApp: directory.appendingPathComponent("ConstellationBar.app"), version: "v1.0.0", parentPID: 1)
            receipt.state = .succeeded
            try receipt.save()
            completed.append(directory)
        }
        UpdateTransaction.pruneReceipts(beside: fixture.receipt.destination, preserving: completed[0])
        XCTAssertEqual(completed.filter { FileManager.default.fileExists(atPath: $0.path) }.count, 5)
        XCTAssertTrue(FileManager.default.fileExists(atPath: completed[0].path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.receipt.receiptURL.path), "Prepared transaction must remain available")
    }

    func testStartupAcknowledgmentRequiresMatchingReceiptTokenVersionAndDestination() throws {
        let fixture = try Fixture()
        let contents = fixture.receipt.destination.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "test.update.fixture", "CFBundleShortVersionString": "1.0.0", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        let bundle = try XCTUnwrap(Bundle(url: fixture.receipt.destination))
        let arguments = ["fixture", "--update-receipt", fixture.receipt.receiptURL.path, "--update-token", fixture.receipt.token]
        UpdateTransaction.acknowledgeStartup(arguments: arguments, bundle: bundle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.receipt.acknowledgmentURL.path), "Prepared update has not been launched")
        var receipt = fixture.receipt
        receipt.state = .awaitingStartup
        receipt.installerPID = 321
        try receipt.save()
        XCTAssertEqual(UpdateTransaction.installerPIDForStartup(arguments: arguments, bundle: bundle), 321)
        XCTAssertNil(UpdateTransaction.installerPIDForStartup(arguments: Array(arguments.dropLast()) + ["invalid"], bundle: bundle))
        UpdateTransaction.acknowledgeStartup(arguments: Array(arguments.dropLast()) + ["invalid"], bundle: bundle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: receipt.acknowledgmentURL.path))
        UpdateTransaction.acknowledgeStartup(arguments: arguments, bundle: bundle)
        let acknowledgment = try JSONDecoder().decode(UpdateStartupAcknowledgment.self, from: Data(contentsOf: receipt.acknowledgmentURL))
        XCTAssertEqual(acknowledgment.token, receipt.token)
        XCTAssertEqual(acknowledgment.pid, ProcessInfo.processInfo.processIdentifier)
    }

    func testHelperRevalidatesBeforeTouchingInstalledApp() throws {
        let fixture = try Fixture()
        XCTAssertThrowsError(try UpdateTransaction.runHelper(receiptURL: fixture.receipt.receiptURL))
        XCTAssertEqual(fixture.identity(fixture.receipt.destination), "old")
        XCTAssertEqual(fixture.identity(fixture.receipt.stagedApp), "new")
        XCTAssertNil(fixture.identity(fixture.receipt.backup))
        let receipt = try UpdateReceipt.load(fixture.receipt.receiptURL)
        XCTAssertEqual(receipt.state, .prepared)
        XCTAssertTrue(receipt.error!.contains("Installer verification failed"))
        try fixture.assertConfigurationUntouched()
    }

    func testReceiptRejectsEscapeAndSymlink() throws {
        let fixture = try Fixture()
        let escaped = UpdateReceipt(token: UUID().uuidString, destination: URL(fileURLWithPath: "/Other.app"), stagedApp: fixture.receipt.stagedApp, version: "1.0.0", parentPID: 1)
        try escaped.save()
        XCTAssertThrowsError(try UpdateReceipt.load(escaped.receiptURL))
        try fixture.receipt.save()
        let alias = fixture.root.appendingPathComponent("alias.json")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.receipt.receiptURL)
        XCTAssertThrowsError(try UpdateReceipt.load(alias))
    }
}
