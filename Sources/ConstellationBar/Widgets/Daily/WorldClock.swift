import Foundation

struct WorldClockReading: Equatable { var name: String; var time: String; var offset: String; var daylightSaving: Bool }
enum WorldClock {
    static func readings(identifiers: [String], date: Date, local: TimeZone = .current) -> [WorldClockReading] {
        identifiers.compactMap { identifier in
            guard let zone = TimeZone(identifier: identifier) else { return nil }
            let formatter = DateFormatter(); formatter.timeZone = zone; formatter.dateFormat = "HH:mm"
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
            var localCalendar = calendar; localCalendar.timeZone = local
            let remote = calendar.dateComponents([.year, .month, .day], from: date)
            let here = localCalendar.dateComponents([.year, .month, .day], from: date)
            let neutral = Calendar(identifier: .gregorian)
            let delta = neutral.dateComponents([.day], from: neutral.date(from: here)!, to: neutral.date(from: remote)!).day ?? 0
            let name = identifier.split(separator: "/").last.map(String.init)?.replacingOccurrences(of: "_", with: " ") ?? identifier
            let offset = delta == 0 ? "Today" : delta > 0 ? "+\(delta) day" : "\(delta) day"
            return WorldClockReading(name: name, time: formatter.string(from: date), offset: offset + " · " + (zone.abbreviation(for: date) ?? identifier), daylightSaving: zone.isDaylightSavingTime(for: date))
        }
    }
}
