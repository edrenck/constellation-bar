import Foundation
import AppKit


struct ProviderPreferences: Codable, Equatable {
    var disabled: [String] = []
    init(disabled: [String] = []) { self.disabled = disabled }
    private enum CodingKeys: String, CodingKey { case disabled }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        disabled = try values.decodeIfPresent([String].self, forKey: .disabled) ?? []
    }
    func includes(_ id: String) -> Bool { !disabled.contains(id) }
}
