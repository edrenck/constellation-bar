import Foundation
import AppKit


enum CalendarProviderChoice: String, Codable, CaseIterable {
    case appleCalendar, outlook
    var title: String { self == .appleCalendar ? "Apple Calendar" : "Outlook for Mac" }
}

struct ProviderPreferences: Codable, Equatable {
    var calendarProvider: CalendarProviderChoice = .appleCalendar
    var disabled: [String] = []
    init(disabled: [String] = []) { self.disabled = disabled }
    private enum CodingKeys: String, CodingKey { case disabled, calendarProvider }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        calendarProvider = try values.decodeIfPresent(CalendarProviderChoice.self, forKey: .calendarProvider) ?? .appleCalendar
        disabled = try values.decodeIfPresent([String].self, forKey: .disabled) ?? []
    }
    func includes(_ id: String) -> Bool { !disabled.contains(id) }
}
