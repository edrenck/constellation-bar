import Foundation

/// One visibility query: unknown displays stay visible and remain distinguishable
/// from displays positively identified as ordinary desktop Spaces.
struct FullscreenSnapshot: Equatable {
    let requestedDisplays: Set<UInt32>
    let coveredDisplays: Set<UInt32>
    let unavailableDisplays: Set<UInt32>

    static let disabled = FullscreenSnapshot(requestedDisplays: [], coveredDisplays: [], unavailableDisplays: [])

    func diagnosticEntry() -> DiagnosticEntry {
        guard !requestedDisplays.isEmpty else {
            return DiagnosticEntry(title: "Fullscreen visibility", health: .disabled,
                detail: "Fullscreen hiding is off on all active bar displays.", widget: nil)
        }
        let unavailable = unavailableDisplays.count
        let detail: String
        if unavailable == requestedDisplays.count {
            detail = "Fullscreen detection is unavailable. The bar stays visible rather than guessing. Refresh status to retry."
        } else if unavailable > 0 {
            detail = "Fullscreen detection is unavailable on \(unavailable) of \(requestedDisplays.count) displays. Bars on those displays stay visible. Refresh status to retry."
        } else {
            detail = "Native Space detection is available on \(requestedDisplays.count) \(requestedDisplays.count == 1 ? "display" : "displays") · \(coveredDisplays.count) fullscreen."
        }
        return DiagnosticEntry(title: "Fullscreen visibility", health: unavailable > 0 ? .attention : .ready, detail: detail, widget: nil)
    }
}
