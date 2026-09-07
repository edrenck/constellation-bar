import Foundation
signal(SIGUSR1, SIG_IGN)
if CommandLine.arguments.contains("--browser-host") { BrowserBridge.runHost(); exit(0) }
import AppKit

// AeroSpace callbacks can arrive while AppKit is initializing, including preview mode.
signal(SIGUSR1, SIG_IGN)
let app = NSApplication.shared
if let index = CommandLine.arguments.firstIndex(of: "--render-previews"), CommandLine.arguments.indices.contains(index + 1) {
    do { try PreviewRenderer.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
    catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
} else {
    let appDelegate = AppDelegate()
    app.delegate = appDelegate
    app.run()
}
