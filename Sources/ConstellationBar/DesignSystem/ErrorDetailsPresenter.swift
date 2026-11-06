import AppKit

/// One bounded, selectable presentation for complete action and persistence errors.
enum ErrorDetailsPresenter {
    static func present(_ error: String, title: String, explanation: String, accessibilityLabel: String, for window: NSWindow) {
        guard window.attachedSheet == nil else { return }
        let alert = NSAlert(); alert.alertStyle = .warning
        alert.messageText = title; alert.informativeText = explanation
        let width = min(440, max(180, window.frame.width-100))
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: 180))
        scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false; text.isSelectable = true; text.string = error
        text.font = .systemFont(ofSize: 13); text.textContainerInset = NSSize(width: 8, height: 8)
        text.isHorizontallyResizable = false; text.isVerticallyResizable = true
        text.autoresizingMask = .width; text.textContainer?.widthTracksTextView = true
        text.setAccessibilityLabel(accessibilityLabel)
        scroll.documentView = text; alert.accessoryView = scroll
        alert.beginSheetModal(for: window)
    }
}
