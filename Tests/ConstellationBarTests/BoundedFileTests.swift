import Foundation
import Darwin
import XCTest
@testable import ConstellationBar

final class BoundedFileTests: XCTestCase {
    func testLimitRejectsOversizedFilesAndSpecialFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("data")
        try Data(repeating: 65, count: 16).write(to: file)
        XCTAssertEqual(BoundedFile.read(file, maximumBytes: 16)?.count, 16)
        XCTAssertNil(BoundedFile.read(file, maximumBytes: 15))
        XCTAssertNil(BoundedFile.read(root, maximumBytes: 16))
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertNil(BoundedFile.read(link, maximumBytes: 16))
        let fifo = root.appendingPathComponent("fifo")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        XCTAssertNil(BoundedFile.read(fifo, maximumBytes: 16))
    }
}
