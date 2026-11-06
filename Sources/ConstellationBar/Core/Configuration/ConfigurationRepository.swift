import Foundation

// Absent default files use defaults; explicit read errors and malformed files remain errors.
enum ConfigurationError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

enum ConfigurationSaveResult: Equatable {
    case saved(URL)
    case failed(String)
    var succeeded: Bool { if case .saved = self { return true }; return false }
    var error: String? { if case let .failed(message) = self { return message }; return nil }
}

/// Owns file validation, error state, backup and atomic persistence; paths are injected.
final class ConfigurationRepository {
    private let resolveActiveURL: () -> URL?
    private let resolveWritableURL: () -> URL
    private(set) var lastError: String?
    private(set) var lastSaveError: String?
    var diagnosticError: String? { lastError ?? lastSaveError }
    init(activeURL: @escaping () -> URL?, writableURL: @escaping () -> URL) {
        resolveActiveURL = activeURL; resolveWritableURL = writableURL
    }
    func load() -> BarConfig {
        guard let url = resolveActiveURL() else { lastError = nil; return .default }
        do {
            let config = try BarConfig.decode(Data(contentsOf: url))
            lastError = nil
            return config
        } catch {
            lastError = "\(url.path): \(error.localizedDescription)"
            return .default
        }
    }

    func saveResult(_ config: BarConfig, to destination: URL? = nil,
                           write: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) -> ConfigurationSaveResult {
        do {
            // Retry checks current disk state instead of treating a past read error as a lock.
            if destination == nil, lastError != nil {
                _ = load()
                if let lastError { throw ConfigurationError.invalid("Fix or move the invalid config before saving. \(lastError)") }
            }
            let url = destination ?? resolveWritableURL()
            let data = try config.encoded()
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: url.path) {
                // Even explicit destinations must not silently replace a malformed file.
                do { _ = try BarConfig.decode(Data(contentsOf: url)) }
                catch { throw ConfigurationError.invalid("Fix or move the invalid config before saving. \(url.path): \(error.localizedDescription)") }
                let backup = url.appendingPathExtension("backup")
                if !FileManager.default.fileExists(atPath: backup.path) { try FileManager.default.copyItem(at: url, to: backup) }
            }
            try write(data, url)
            lastSaveError = nil
            return .saved(url)
        } catch {
            lastSaveError = error.localizedDescription
            return .failed(error.localizedDescription)
        }
    }

}
