import Foundation

/// Read-only adapter for the Nostromo-i calendar schema shipped by Outlook
/// 16.112.4. No Outlook framework is loaded and no network client is created.
/// The directory, not a scan of abandoned compressed blocks, defines liveness.
enum OutlookCacheReader {
    private static let magic = Data([5, 0x6a, 0x70, 0x3b, 0x64, 0x45, 2, 0x5d])
    private static var unsupported: OutlookCacheError {
        .message("This Outlook cache format is not supported. Update ConstellationBar or choose Apple Calendar.")
    }
    private static var changing: OutlookCacheError {
        .message("Outlook is updating its local cache. Retrying shortly.")
    }
    static func read(now: Date = Date()) throws -> AgendaState {
        try OutlookCacheAccess.withFolder { root in
            let profiles = root.appendingPathComponent("Outlook 15 Profiles", isDirectory: true)
            let folders = try FileManager.default.contentsOfDirectory(at: profiles, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            var states: [AgendaState] = []
            for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let file = folder.appendingPathComponent("HxStore.hxd")
                guard FileManager.default.fileExists(atPath: file.path) else { continue }
                let before = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])
                guard before.isRegularFile == true, let size = before.fileSize,
                      size <= OutlookCacheContainer.maximumFileBytes else { throw unsupported }
                // Owned bytes: Outlook may truncate or replace its live file.
                let bytes = try Data(contentsOf: file)
                let after = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                guard before.fileSize == after.fileSize, before.contentModificationDate == after.contentModificationDate,
                      bytes.count == size else { throw changing }
                states.append(try decode(bytes, profile: folder.lastPathComponent, now: now))
            }
            guard !states.isEmpty else { throw OutlookCacheError.message("No supported Outlook cache was found. Open Outlook and let its calendars sync, then choose its data folder again.") }
            return AgendaState(authorized: true, message: "Outlook’s local cache · refreshed by Outlook", calendars: states.flatMap(\.calendars),
                               events: states.flatMap(\.events).sorted { $0.start < $1.start }, rangeStart: states.first?.rangeStart, rangeEnd: states.first?.rangeEnd)
        }
    }

    /// Five-byte directory slots hold a 256-byte address unit and allocation
    /// length. Bit zero marks a deleted slot. Two directory generations have
    /// separate CRCs; the committed selector at 0x2c chooses the active one.
    static func liveBlocks(_ bytes: Data) throws -> [Data] {
        guard bytes.count >= 0xc0, bytes.count <= OutlookCacheContainer.maximumFileBytes,
              bytes.prefix(8) == Data("Nostromo".utf8), u64(bytes, 8) == 0x69,
              u64(bytes, 0x38) == 4096, u32(bytes, 0x2c) <= 1 else { throw unsupported }
        let descriptor = 0x58 + Int(u32(bytes, 0x2c)) * 32
        let baseValue = u64(bytes, descriptor), slots = Int(u32(bytes, 0x48))
        guard baseValue <= UInt64(bytes.count), slots > 0, slots <= 1_000_000 else { throw unsupported }
        let base = Int(baseValue), length = slots * 5
        guard base >= 0xc0, length <= bytes.count - base,
              OutlookCacheContainer.crc(bytes[base..<base+length]) == u32(bytes, descriptor+24) else { throw changing }
        var result: [Data] = [], total = 0, visited: Set<Int> = []
        for slot in 0..<slots {
            let entry = base + slot*5, unit = u32(bytes, entry)
            guard unit != 0, unit & 1 == 0 else { continue }
            let offset = UInt64(unit) * 256
            guard offset <= UInt64(bytes.count), bytes.count - Int(offset) >= 48 else { throw changing }
            let p = Int(offset)
            guard visited.insert(p).inserted else { throw unsupported }
            guard bytes[p+8..<p+16] == magic,
                  OutlookCacheContainer.crc(bytes[p+4..<p+32]) == u32(bytes, p) else { throw changing }
            let type = u32(bytes, p+16)
            guard type == 8 || type == 16, u32(bytes, p+28) == 4 else { throw unsupported }
            let header = type == 8 ? 40 : 48
            let compressed = Int(u32(bytes, p+20)), inflated = Int(u32(bytes, p+24))
            guard compressed <= OutlookCacheContainer.maximumBlockBytes,
                  inflated <= OutlookCacheContainer.maximumBlockBytes,
                  compressed <= bytes.count-p-header,
                  OutlookCacheContainer.crc(bytes[p+8..<p+header+compressed]) == u32(bytes, p+4) else { throw changing }
            // Type 16 contains storage metadata, not calendar objects.
            guard type == 8 else { continue }
            guard let payload = OutlookCacheContainer.inflate(Array(bytes[p+header..<p+header+compressed]), size: inflated) else { throw unsupported }
            total += payload.count
            guard total <= 512 * 1024 * 1024 else { throw unsupported }
            result.append(payload)
        }
        return result
    }

    struct Record {
        let bytes: Data
        let type: UInt16
        let fixed: Int
        var id: UInt64 { OutlookCacheReader.u64(bytes, 16) }
        var occurrence: UInt64 { OutlookCacheReader.u64(bytes, 8) }
        func string(at field: Int) throws -> String {
            let offset = Int(OutlookCacheReader.u32(bytes, field))
            let descriptor = OutlookCacheReader.u32(bytes, field+4)
            let length = Int(descriptor & 0x7fff_ffff)
            let pool = fixed - 4 + (descriptor & 0x8000_0000 == 0 ? 0 : Int(OutlookCacheReader.u32(bytes, 100)))
            guard length <= 64 * 1024, length % 2 == 0, pool <= bytes.count, offset <= bytes.count-pool,
                  length <= bytes.count-pool-offset else { throw OutlookCacheReader.unsupported }
            if length == 0 { return "" }
            guard let value = String(data: bytes[pool+offset..<pool+offset+length], encoding: .utf16LittleEndian) else { throw OutlookCacheReader.unsupported }
            return value.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        }
    }

    /// Serialized object frames repeat their byte length around a format-5
    /// prefix and carry an explicit fixed-schema size and object type. Index
    /// pages also embed these frames. Only complete, supported frames are read.
    static func records(in payload: Data) throws -> [Record] {
        guard payload.count >= 120 else { return [] }
        var result: [Record] = [], p = 8
        while p <= payload.count-112 {
            let size = Int(u32(payload, p))
            guard size >= 112, size <= payload.count-p, u32(payload, p-8) == size,
                  u16(payload, p-4) == 5, u16(payload, p+4) == 0 else { p += 1; continue }
            let type = u16(payload, p+6), fixed = Int(u16(payload, p-2))
            guard type == 0x6b || type == 0x68 else { p += 1; continue }
            guard (type == 0x6b && fixed == 1175) || (type == 0x68 && fixed == 977), size >= fixed else { throw unsupported }
            result.append(Record(bytes: Data(payload[p..<p+size]), type: type, fixed: fixed))
            p += size
        }
        return result
    }

    static func decode(_ bytes: Data, profile: String, now: Date) throws -> AgendaState {
        let records = try liveBlocks(bytes).flatMap { try self.records(in: $0) }
        let prefix = "outlook:" + profile + ":"
        var calendars: [UInt64: CalendarSource] = [:]
        for record in records where record.type == 0x68 {
            let title = try record.string(at: 776)
            guard !title.isEmpty else { continue }
            calendars[record.id] = CalendarSource(id: prefix + String(record.id), title: title, account: "Outlook")
        }
        guard !calendars.isEmpty else { throw OutlookCacheError.message("Outlook has not cached any calendars yet. Open its Calendar view and let it sync.") }
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now))!
        let end = calendar.date(byAdding: .day, value: 31, to: start)!
        var events: [String: AgendaEvent] = [:]
        for record in records where record.type == 0x6b {
            guard let source = calendars[u64(record.bytes, 220)] else { continue }
            let allDay = record.bytes[1142] & 8 != 0
            var begin = try date(u64(record.bytes, 628)), finish = try date(u64(record.bytes, 636))
            // Outlook stores all-day dates at UTC midnight; retain those civil
            // dates when displaying them in the user's local time zone.
            if allDay {
                var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
                guard let localStart = calendar.date(from: utc.dateComponents([.year, .month, .day], from: begin)),
                      let localEnd = calendar.date(from: utc.dateComponents([.year, .month, .day], from: finish)) else { throw unsupported }
                begin = localStart; finish = localEnd
            }
            guard finish > begin else { throw unsupported }
            guard begin < end, finish > start else { continue }
            let title = try record.string(at: 1084)
            let id = prefix + String(record.id) + ":" + String(record.occurrence)
            let event = AgendaEvent(id: id, calendarID: source.id, title: title.isEmpty ? "Untitled event" : title,
                                    calendar: source.title, start: begin, end: finish, allDay: allDay,
                                    location: "", meetingURL: nil, attendees: [])
            if let previous = events[id], previous.start != begin || previous.end != finish || previous.title != event.title {
                throw changing
            }
            events[id] = event
        }
        return AgendaState(authorized: true, calendars: calendars.values.sorted { $0.title < $1.title },
                           events: events.values.sorted { $0.start < $1.start }, rangeStart: start, rangeEnd: end)
    }
    private static func date(_ ticks: UInt64) throws -> Date {
        guard ticks >= 599266080000000000, ticks <= 662380416000000000 else { throw unsupported }
        return Date(timeIntervalSince1970: (Double(ticks)-621355968000000000)/10_000_000)
    }
    static func u16(_ b: Data, _ p: Int) -> UInt16 { UInt16(b[p]) | UInt16(b[p+1]) << 8 }
    static func u32(_ b: Data, _ p: Int) -> UInt32 { (0..<4).reduce(0) { $0 | UInt32(b[p+$1]) << ($1*8) } }
    static func u64(_ b: Data, _ p: Int) -> UInt64 { (0..<8).reduce(0) { $0 | UInt64(b[p+$1]) << ($1*8) } }
}
