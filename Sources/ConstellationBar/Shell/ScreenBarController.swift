import AppKit
import Foundation
import QuartzCore

final class ScreenBarController {
    private var config: BarConfig
    private var windows: [NSScreen: BarWindow] = [:]
    private var visibilityTimer: Timer?
    private var frameTimer: Timer?
    weak var interactionDelegate: BarInteractionDelegate? {
        didSet { windows.values.forEach { $0.barView.interactionDelegate = interactionDelegate } }
    }

    init(config: BarConfig) {
        self.config = config
    }

    func apply(config: BarConfig) {
        self.config = config
        if Set(windows.keys.map(\.configurationID)) != Set(targetScreens.map(\.configurationID)) {
            installBars()
        } else {
            for (screen, window) in windows {
                let local = config.forDisplay(screen.configurationID)
                window.updateFrame(screen: screen, config: local)
                window.barView.apply(config: local)
            }
        }
        if let latestState { render(state: latestState) }
    }

    private var latestState: BarState?
    private var targetScreens: [NSScreen] {
        let screens = config.displayMode == .primaryOnly ? Array(NSScreen.screens.prefix(1)) : NSScreen.screens
        return screens.filter { config.displayOverrides[$0.configurationID]?.enabled != false }
    }

    func installBars() {
        closeBars()
        for screen in targetScreens {
            let window = BarWindow(screen: screen, config: config.forDisplay(screen.configurationID))
            window.barView.interactionDelegate = interactionDelegate
            windows[screen] = window
            window.orderFrontRegardless()
        }
        startVisibilityTimer()
    }

    func closeBars() {
        for window in windows.values {
            window.close()
        }
        windows.removeAll()
        visibilityTimer?.invalidate()
        visibilityTimer = nil
        frameTimer?.invalidate(); frameTimer = nil
    }

    func render(state: BarState) {
        latestState = state
        for (screen, window) in windows {
            var local = state
            let index = (NSScreen.screens.firstIndex(of: screen) ?? 0) + 1
            if config.workspacesOnCurrentDisplay {
                local.workspaces = state.workspaces.filter { $0.monitorIndex == nil || $0.monitorIndex == index }
                if let focused = local.focusedWindow, !focused.workspace.isEmpty,
                   !local.workspaces.contains(where: { $0.name == focused.workspace }) { local.focusedWindow = nil }
            }
            window.barView.render(state: local)
        }
    }

    private func startVisibilityTimer() {
        visibilityTimer?.invalidate()
        visibilityTimer = Timer.scheduledTimer(withTimeInterval: 0.20, repeats: true) { [weak self] _ in
            self?.updateWindowVisibilityAndFrames()
        }
        RunLoop.main.add(visibilityTimer!, forMode: .common)
        frameTimer?.invalidate()
        frameTimer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            for (screen, window) in self.windows {
                window.updateFrame(screen: screen, config: self.config.forDisplay(screen.configurationID))
            }
        }
        RunLoop.main.add(frameTimer!, forMode: .common)
        updateWindowVisibilityAndFrames()
    }

    private func updateWindowVisibilityAndFrames() {
        let covering = FullscreenDetector.coveredDisplays()
        for (screen, window) in windows {
            let local = config.forDisplay(screen.configurationID)
            if local.hideInFullscreen && covering.contains(screen.displayID) {
                window.orderOut(nil)
            } else if !window.isVisible {
                window.orderFrontRegardless()
            }
        }
    }
}

final class BarWindow: NSPanel {
    let barView: BarRootView
    private var avoidingMenuBar = false
    private var menuTransition = MenuBarTransition()
    private var targetFrame: NSRect?
    private var movementTimer: Timer?

    init(screen: NSScreen, config: BarConfig) {
        let initialAvoidance = MenuBarVisibilityDetector.isVisible(on: screen)
        self.avoidingMenuBar = initialAvoidance
        self.menuTransition = MenuBarTransition(avoiding: initialAvoidance)
        let rect = BarWindow.frame(for: screen, config: config, avoidingMenuBar: initialAvoidance)
        self.barView = BarRootView(frame: NSRect(origin: .zero, size: rect.size), config: config)

        super.init(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isMovable = false
        ignoresMouseEvents = false
        contentView = barView
        setFrame(rect, display: true)
        targetFrame = rect
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func close() {
        movementTimer?.invalidate(); movementTimer = nil
        super.close()
    }

    func move(to destination: NSRect, animated: Bool) {
        movementTimer?.invalidate(); movementTimer = nil
        guard animated else {
            setFrame(destination, display: true); barView.needsLayout = true; return
        }
        let origin = frame, start = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let progress = min(1, (ProcessInfo.processInfo.systemUptime - start) / 0.20)
            self.setFrame(BarFrameMotion.interpolate(from: origin, to: destination, progress: progress), display: true)
            self.barView.needsLayout = true
            if progress >= 1 { timer.invalidate(); self.movementTimer = nil }
        }
        movementTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func updateFrame(screen: NSScreen, config: BarConfig) {
        let mouse = NSEvent.mouseLocation
        let distance = screen.frame.maxY - mouse.y
        let onDisplay = mouse.x >= screen.frame.minX && mouse.x < screen.frame.maxX && distance >= 0 && mouse.y >= screen.frame.minY
        let atEdge = onDisplay && distance <= 2
        let inMenu = onDisplay && distance <= max(NSStatusBar.system.thickness, screen.frame.maxY - screen.visibleFrame.maxY)
        // Let macOS receive the edge gesture instead of intercepting it with this panel.
        ignoresMouseEvents = atEdge
        avoidingMenuBar = menuTransition.update(visible: MenuBarVisibilityDetector.isVisible(on: screen), now: ProcessInfo.processInfo.systemUptime, atEdge: atEdge, inMenuRegion: inMenu)
        let rect = BarWindow.frame(for: screen, config: config, avoidingMenuBar: avoidingMenuBar)
        guard targetFrame != rect else { return }
        let oldTarget = targetFrame
        targetFrame = rect
        let sizeChanged = oldTarget?.size != rect.size
        if sizeChanged {
            barView.frame = NSRect(origin: .zero, size: rect.size)
            barView.apply(config: config)
        }
        move(to: rect, animated: isVisible && !sizeChanged && oldTarget?.minX == rect.minX && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    private static func frame(for screen: NSScreen, config: BarConfig, avoidingMenuBar: Bool) -> NSRect {
        let frame = screen.frame
        let menuBarHeight = max(NSStatusBar.system.thickness, frame.maxY - screen.visibleFrame.maxY)
        let clearance = avoidingMenuBar ? menuBarHeight : 0
        let totalHeight = config.height + config.coveEdgeDepth
        let y = frame.maxY - totalHeight - clearance - config.topInset
        return NSRect(x: frame.minX, y: y, width: frame.width, height: totalHeight)
    }
}

enum BarFrameMotion {
    static func interpolate(from: NSRect, to: NSRect, progress: Double) -> NSRect {
        let t = max(0, min(1, progress))
        let eased = t * t * (3 - 2 * t)
        return NSRect(x: from.minX + (to.minX - from.minX) * eased,
                      y: from.minY + (to.minY - from.minY) * eased,
                      width: from.width + (to.width - from.width) * eased,
                      height: from.height + (to.height - from.height) * eased)
    }
}

/// A short dwell at the actual edge makes room for macOS to reveal its menu.
/// Ordinary movement within the bar cannot initiate or retain the displacement.
struct MenuBarTransition {
    private(set) var avoiding = false
    private var hiddenSince: TimeInterval?
    private var edgeSince: TimeInterval?
    init(avoiding: Bool = false) { self.avoiding = avoiding }
    mutating func update(visible: Bool, now: TimeInterval, atEdge: Bool = false, inMenuRegion: Bool = false) -> Bool {
        if atEdge { if edgeSince == nil { edgeSince = now } } else { edgeSince = nil }
        let edgeRequested = edgeSince.map { now - $0 >= 0.10 } ?? false
        if visible || edgeRequested || (avoiding && inMenuRegion) { avoiding = true; hiddenSince = nil }
        else if avoiding {
            if hiddenSince == nil { hiddenSince = now }
            if now - (hiddenSince ?? now) >= 0.12 { avoiding = false; hiddenSince = nil }
        }
        return avoiding
    }
}

enum MenuBarVisibilityDetector {
    static func isVisible(on screen: NSScreen) -> Bool {
        guard NSMenu.menuBarVisible() else { return false }
        guard NSScreen.screens.count > 1 else { return true }
        // AppKit's signal is global. On multiple displays, match actual on-screen
        // menu-bar windows to this display rather than guessing from the pointer.
        let display = CGDisplayBounds(screen.displayID)
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        return windows.contains { window in
            guard (window[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.mainMenuWindow)),
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"], let width = bounds["Width"], let height = bounds["Height"] else { return false }
            return width >= display.width * 0.8 && height > 0 && height <= 100 &&
                abs(x - display.minX) < 2 && abs(y - display.minY) < 2
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }
    var configurationID: String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return String(displayID) }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

enum FullscreenDetector {
    static func covers(_ window: CGRect, display: CGRect) -> Bool {
        abs(window.minX - display.minX) <= 2 && abs(window.minY - display.minY) <= 2 &&
        abs(window.width - display.width) <= 2 && abs(window.height - display.height) <= 2
    }
    static func coveredDisplays() -> Set<CGDirectDisplayID> {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        var covered = Set<CGDirectDisplayID>()
        for window in info {
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            if ["ConstellationBar", "Window Server", "Dock"].contains(owner) { continue }
            guard (window[kCGWindowLayer as String] as? Int ?? 0) == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"], let w = bounds["Width"], let h = bounds["Height"] else { continue }
            let rect = CGRect(x: x, y: y, width: w, height: h)
            for screen in NSScreen.screens where covers(rect, display: CGDisplayBounds(screen.displayID)) { covered.insert(screen.displayID) }
        }
        return covered
    }
}
