import Foundation
import AppKit

// AeroSpace callbacks can arrive while AppKit is initializing, including preview mode.
signal(SIGUSR1, SIG_IGN)
if let index = CommandLine.arguments.firstIndex(of: "--install-update"), CommandLine.arguments.indices.contains(index + 1) {
    do { try UpdateTransaction.runHelper(receiptURL: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
    catch { fputs("Update installation failed: \(error.localizedDescription)\n", stderr); exit(1) }
} else if CommandLine.arguments.contains("--diagnose-providers") {
    _ = NSApplication.shared
    let codex = CodexAgentStatusIntegration().snapshot()
    let native = NativeMediaIntegration().sessions()
    let music = AppleMusicIntegration(automaticallyRequestsAccess: false).sessions()
    let diagnostics: [String: Any] = [
        "codex": ["available": codex.available, "active": codex.activeCount, "idle": codex.idleCount, "unknown": codex.unknownCount, "message": codex.message],
        "nativeMedia": ["sessions": native.sessions.count, "message": native.status],
        "appleMusic": ["sessions": music.sessions.count, "message": music.status]
    ]
    if let data = try? JSONSerialization.data(withJSONObject: diagnostics, options: [.prettyPrinted, .sortedKeys]) {
        print(String(decoding: data, as: UTF8.self))
    }
} else if let index = CommandLine.arguments.firstIndex(of: "--render-previews"), CommandLine.arguments.indices.contains(index + 1) {
    _ = NSApplication.shared
    do { try PreviewRenderer.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
    catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
} else {
    let app = NSApplication.shared
    let appDelegate = AppDelegate()
    app.delegate = appDelegate
    // NSApplication.delegate is weak; keep the delegate and its controllers alive
    // for the entire event loop, including delayed startup checks.
    withExtendedLifetime(appDelegate) { app.run() }
}
