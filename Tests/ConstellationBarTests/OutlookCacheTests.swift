import XCTest
@testable import ConstellationBar

final class OutlookCacheTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testCommittedDirectoryExcludesAbandonedAndDeletedEvents() throws {
        let calendar = frame(type: 0x68, id: 11, title: "Personal")
        let old = frame(type: 0x6b, id: 22, title: "Old time", start: now)
        let current = frame(type: 0x6b, id: 22, title: "Updated", start: now.addingTimeInterval(3600))
        let deleted = frame(type: 0x6b, id: 23, title: "Deleted", start: now)
        var bytes = store([calendar, old, current, deleted], active: [0, 2], tombstones: [3])
        let state = try OutlookCacheReader.decode(bytes, profile: "Profile", now: now)
        XCTAssertEqual(state.events.map(\.title), ["Updated"])
        XCTAssertEqual(state.events.first?.start, now.addingTimeInterval(3600))
        // An invalid active directory must not fall back to scanning old blocks.
        bytes[0x100] ^= 2
        XCTAssertThrowsError(try OutlookCacheReader.decode(bytes, profile: "Profile", now: now))
    }

    func testOccurrencesKeepSeparateIdentitiesAndUnicodeTitles() throws {
        let first = frame(type: 0x6b, id: 22, occurrence: 100, title: "Réunion 🌟", start: now)
        let second = frame(type: 0x6b, id: 22, occurrence: 200, title: "Réunion 🌟", start: now.addingTimeInterval(86400))
        let bytes = store([frame(type: 0x68, id: 11, title: "Work"), first, second, first], active: [0,1,2,3])
        let state = try OutlookCacheReader.decode(bytes, profile: "A", now: now)
        XCTAssertEqual(state.events.count, 2)
        XCTAssertEqual(Set(state.events.map(\.id)).count, 2)
        XCTAssertEqual(state.events.first?.title, "Réunion 🌟")
        XCTAssertEqual(state.events.first?.calendar, "Work")
        let other = try OutlookCacheReader.decode(bytes, profile: "B", now: now)
        XCTAssertNotEqual(state.events.first?.id, other.events.first?.id)
    }

    func testConflictAndUnsupportedSchemaFailInsteadOfInventingAnAgenda() throws {
        let calendar = frame(type: 0x68, id: 11, title: "Work")
        let first = frame(type: 0x6b, id: 22, title: "One", start: now)
        let conflicting = frame(type: 0x6b, id: 22, title: "Other", start: now)
        XCTAssertThrowsError(try OutlookCacheReader.decode(store([calendar, first, conflicting], active: [0,1,2]), profile: "A", now: now))
        var unknown = first; put(1176, at: 6, count: 2, in: &unknown)
        XCTAssertThrowsError(try OutlookCacheReader.records(in: unknown))
        var truncated = first; put(0x7ffffffe, at: 8+1088, in: &truncated)
        XCTAssertThrowsError(try OutlookCacheReader.decode(store([calendar, truncated], active: [0,1]), profile: "A", now: now))
    }

    func testAllDayPreservesCivilDateAndMultiDayDuration() throws {
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnight = utc.startOfDay(for: now)
        let event = frame(type: 0x6b, id: 22, title: "Holiday", start: midnight, duration: 172800, allDay: true)
        let state = try OutlookCacheReader.decode(store([frame(type: 0x68, id: 11, title: "Personal"), event], active: [0,1]), profile: "A", now: now)
        let result = try XCTUnwrap(state.events.first)
        XCTAssertTrue(result.allDay)
        XCTAssertEqual(Calendar.current.component(.hour, from: result.start), 0)
        XCTAssertEqual(Calendar.current.component(.day, from: result.start), utc.component(.day, from: midnight))
        XCTAssertEqual(Calendar.current.dateComponents([.day], from: result.start, to: result.end).day, 2)
    }

    func testWrongVersionAndBrokenPayloadAreRejected() throws {
        var bytes = store([frame(type: 0x68, id: 11, title: "Calendar")], active: [0])
        bytes[8] = 0x70
        XCTAssertThrowsError(try OutlookCacheReader.liveBlocks(bytes))
        bytes[8] = 0x69; bytes[0x400+45] ^= 1
        XCTAssertThrowsError(try OutlookCacheReader.liveBlocks(bytes))
    }

    private func frame(type: UInt64, id: UInt64, occurrence: UInt64 = 0, title: String, start: Date? = nil, duration: TimeInterval = 3600, allDay: Bool = false) -> Data {
        let fixed = type == 0x68 ? 977 : 1175
        var record = Data(repeating: 0, count: fixed-4)
        let string = (title + "\0").data(using: .utf16LittleEndian)!
        record.append(string)
        put(UInt64(record.count), at: 0, in: &record)
        put(type, at: 6, count: 2, in: &record)
        put(occurrence, at: 8, count: 8, in: &record)
        put(id, at: 16, count: 8, in: &record)
        let field = type == 0x68 ? 776 : 1084
        put(UInt64(string.count) | 0x80000000, at: field+4, in: &record)
        if type == 0x6b {
            put(11, at: 220, count: 8, in: &record)
            let date = start ?? now
            put(UInt64(date.timeIntervalSince1970 * 10_000_000 + 621355968000000000), at: 628, count: 8, in: &record)
            put(UInt64((date.timeIntervalSince1970+duration) * 10_000_000 + 621355968000000000), at: 636, count: 8, in: &record)
            if allDay { record[1142] |= 8 }
        }
        var framed = Data(repeating: 0, count: 8)
        put(UInt64(record.count), at: 0, in: &framed)
        put(5, at: 4, count: 2, in: &framed)
        put(UInt64(fixed), at: 6, count: 2, in: &framed)
        framed.append(record)
        return framed
    }
    private func store(_ payloads: [Data], active: [Int], tombstones: [Int] = []) -> Data {
        var data = Data(repeating: 0, count: 0x400)
        data.replaceSubrange(0..<8, with: Data("Nostromo".utf8))
        put(0x69, at: 8, count: 8, in: &data)
        put(4096, at: 0x38, count: 8, in: &data)
        put(16, at: 0x48, in: &data)
        put(0x100, at: 0x58, count: 8, in: &data)
        var offsets: [Int] = []
        for payload in payloads {
            offsets.append(data.count)
            var compressed = Data([0xf0]); var length = payload.count-15
            while length >= 255 { compressed.append(255); length -= 255 }
            compressed.append(UInt8(length)); compressed.append(payload)
            var block = Data(repeating: 0, count: 40)
            block.replaceSubrange(8..<16, with: [5,0x6a,0x70,0x3b,0x64,0x45,2,0x5d])
            put(8, at: 16, in: &block); put(UInt64(compressed.count), at: 20, in: &block)
            put(UInt64(payload.count), at: 24, in: &block); put(4, at: 28, in: &block)
            block.append(compressed)
            put(UInt64(OutlookCacheContainer.crc(block[8..<block.count])), at: 4, in: &block)
            put(UInt64(OutlookCacheContainer.crc(block[4..<32])), at: 0, in: &block)
            data.append(block)
            data.append(Data(repeating: 0, count: (512-data.count%512)%512))
        }
        for (slot,index) in active.enumerated() { put(UInt64(offsets[index]/256), at: 0x100+slot*5, in: &data) }
        for (slot,index) in tombstones.enumerated() { put(UInt64(offsets[index]/256)|1, at: 0x100+(slot+active.count)*5, in: &data) }
        put(UInt64(OutlookCacheContainer.crc(data[0x100..<0x150])), at: 0x70, in: &data)
        return data
    }
    private func put(_ value: UInt64, at p: Int, count: Int = 4, in bytes: inout Data) {
        for i in 0..<count { bytes[p+i] = UInt8(truncatingIfNeeded: value >> (i*8)) }
    }
}
