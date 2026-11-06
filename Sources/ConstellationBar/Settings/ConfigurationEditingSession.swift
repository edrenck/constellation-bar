import Foundation

/// Raw text belongs to the editing session until the complete draft validates and saves.
struct ConfigurationFormInput {
    var weather: WeatherSettingsInput?
    var worldClocks: String?
    var timerPresets: String?

    func applying(to draft: BarConfig) throws -> BarConfig {
        var candidate = draft
        if let weather { candidate.weather = try weather.applying(to: candidate.weather) }
        if let worldClocks {
            candidate.widgetPreferences.worldClockIdentifiers = worldClocks.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? [] : pieces(worldClocks)
        }
        if let timerPresets {
            let values = pieces(timerPresets)
            let minutes = values.compactMap(Int.init)
            guard values.count == minutes.count else {
                throw ConfigurationError.invalid("Timer presets must be comma-separated whole minutes from 1 to 1440.")
            }
            candidate.widgetPreferences.timerPresetMinutes = minutes
        }
        try candidate.validate()
        return candidate
    }

    private func pieces(_ text: String) -> [String] {
        text.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}

/// Owns draft validation, persistence and bounded Undo history, independently of AppKit controls.
/// The settings controller uses this synchronously on the main thread; persistence is injected.
final class ConfigurationEditingSession {
    var draft: BarConfig
    var input = ConfigurationFormInput()
    private(set) var saved: BarConfig
    private(set) var error: String?
    private(set) var undoHistory: [BarConfig] = []
    private var pendingUndo = false
    private let persist: (BarConfig) -> ConfigurationSaveResult
    private let historyLimit = 30

    var canUndo: Bool { error == nil && !undoHistory.isEmpty }

    init(config: BarConfig, persist: @escaping (BarConfig) -> ConfigurationSaveResult) {
        draft = config; saved = config; self.persist = persist
    }

    /// A reload establishes a new saved baseline. A failed-save form remains available to retry;
    /// Revert uses the latest saved configuration rather than resurrecting an obsolete baseline.
    func receiveSaved(_ config: BarConfig) {
        guard config.jsonString() != saved.jsonString() else { return }
        saved = config
        undoHistory.removeAll(); pendingUndo = false
        if error == nil { draft = config; input = ConfigurationFormInput() }
    }

    /// Explicit import replaces all pending form input; ordinary control edits mutate only draft.
    func replaceDraft(_ config: BarConfig) {
        draft = config; input = ConfigurationFormInput(); pendingUndo = false
    }

    /// Returns the configuration that may be applied to the desktop, only after a successful write.
    @discardableResult func commit() -> BarConfig? {
        let candidate: BarConfig
        do { candidate = try validatedDraft() }
        catch { self.error = error.localizedDescription; return nil }
        let result = persist(candidate)
        guard result.succeeded else { error = result.error; return nil }
        if pendingUndo, candidate.jsonString() == undoHistory.last?.jsonString() {
            _ = undoHistory.popLast()
        } else if candidate.jsonString() != saved.jsonString() {
            undoHistory.append(saved)
            if undoHistory.count > historyLimit { undoHistory.removeFirst(undoHistory.count - historyLimit) }
        }
        saved = candidate; draft = candidate
        error = nil; pendingUndo = false; input = ConfigurationFormInput()
        return candidate
    }

    /// Export validates the same form as Save, without advancing the desktop or Undo history.
    func validatedDraft() throws -> BarConfig { try input.applying(to: draft) }

    @discardableResult func undo() -> BarConfig? {
        guard canUndo, let previous = undoHistory.last else { return nil }
        draft = previous; pendingUndo = true
        return commit()
    }

    func revert() {
        draft = saved; error = nil; pendingUndo = false; input = ConfigurationFormInput()
    }
}
