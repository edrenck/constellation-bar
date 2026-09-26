import Foundation
import Carbon

struct KeyboardSource: Equatable { var id: String; var name: String; var language: String }
struct KeyboardState: Equatable { var sources: [KeyboardSource] = []; var selectedID = ""; var message = ""; var selected: KeyboardSource? { sources.first { $0.id == selectedID } } }
protocol KeyboardSourceDriving {
    func snapshot() -> KeyboardState
    func select(_ id: String) throws
}
struct SystemKeyboardSourceDriver: KeyboardSourceDriving {
    private func sources() -> [TISInputSource] {
        let filter = [kTISPropertyInputSourceIsSelectCapable as String: true, kTISPropertyInputSourceIsEnabled as String: true] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false) else { return [] }
        return list.takeRetainedValue() as? [TISInputSource] ?? []
    }
    private func string(_ source: TISInputSource, _ key: CFString) -> String {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return "" }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
    func snapshot() -> KeyboardState {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return KeyboardState(message: "The current input source is unavailable.") }
        let values = sources().map { KeyboardSource(id: string($0, kTISPropertyInputSourceID), name: string($0, kTISPropertyLocalizedName), language: "") }
        return KeyboardState(sources: values, selectedID: string(current, kTISPropertyInputSourceID), message: values.isEmpty ? "No enabled input sources are available." : "")
    }
    func select(_ id: String) throws {
        guard let source = sources().first(where: { string($0, kTISPropertyInputSourceID) == id }) else { throw WidgetActionError(message: "This input source is no longer enabled. Add it in Keyboard settings.") }
        let status = TISSelectInputSource(source)
        guard status == noErr else { throw WidgetActionError(message: "macOS could not switch input source (\(status)).") }
    }
}
final class KeyboardProvider: SystemProviding {
    let kinds: Set<WidgetKind> = [.keyboard]
    private let driver: KeyboardSourceDriving
    init(driver: KeyboardSourceDriving = SystemKeyboardSourceDriver()) { self.driver = driver }
    func select(_ id: String) throws { try driver.select(id) }
    func sample(config: BarConfig, into state: inout SystemState) { state.keyboard = driver.snapshot() }
    func merge(snapshot: SystemState, into state: inout SystemState) { state.keyboard = snapshot.keyboard }
}
