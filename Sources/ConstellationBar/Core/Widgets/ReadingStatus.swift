import Foundation

/// Availability travels with a measurement. Numeric storage is never evidence of a successful read.
enum ReadingStatus: Equatable {
    case available
    case waiting
    case failed(String)

    var isAvailable: Bool { self == .available }
    func description(for name: String) -> String {
        switch self {
        case .available: return "\(name) available"
        case .waiting: return "Collecting \(name.lowercased()) readings…"
        case let .failed(message): return message
        }
    }
}
