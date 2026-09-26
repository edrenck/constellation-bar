import AppKit
import Foundation
import QuartzCore
import ApplicationServices

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
            window.barView.displayConfigurationID = screen.configurationID
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
            let index = (NSScreen.screens.firstIndex(of: screen) ?? 0) + 1
            window.barView.render(state: config.stateForDisplay(state, id: screen.configurationID, monitorIndex: index))
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

    init(screen: NSScreen, config: BarConfig, environment: MenuBarEnvironment? = nil) {
        let environment = environment ?? MenuBarEnvironment.capture(on: screen)
        let initialAvoidance = environment.visible
        self.avoidingMenuBar = initialAvoidance
        self.menuTransition = MenuBarTransition(avoiding: initialAvoidance)
        let rect = BarWindow.frame(for: screen, config: config, avoidingMenuBar: initialAvoidance, menuBarHeight: environment.height)
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
        // Render in the system top region so a notched display can use the
        // native left/right safe areas around the camera cutout. The bar's
        // own fullscreen policy still controls whether it is shown there.
        // Do not opt into fullScreenAuxiliary: macOS should own a native
        // fullscreen display without a persistent bar above its video.
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovable = false
        ignoresMouseEvents = false
        contentView = barView
        setFrame(rect, display: true)
        applyContentScale(for: screen, config: config)
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

    func updateFrame(screen: NSScreen, config: BarConfig, environment: MenuBarEnvironment? = nil) {
        let environment = environment ?? MenuBarEnvironment.capture(on: screen)
        let mouse = environment.pointer
        let distance = screen.frame.maxY - mouse.y
        let onDisplay = mouse.x >= screen.frame.minX && mouse.x < screen.frame.maxX && distance >= 0 && mouse.y >= screen.frame.minY
        let atEdge = onDisplay && distance <= 2
        let inMenu = onDisplay && distance <= environment.height
        // Let macOS receive the edge gesture instead of intercepting it with this panel.
        ignoresMouseEvents = atEdge
        avoidingMenuBar = menuTransition.update(visible: environment.visible, now: environment.uptime, atEdge: atEdge, inMenuRegion: inMenu)
        let rect = BarWindow.frame(for: screen, config: config, avoidingMenuBar: avoidingMenuBar, menuBarHeight: environment.height)
        guard targetFrame != rect else { return }
        let oldTarget = targetFrame
        targetFrame = rect
        let sizeChanged = oldTarget?.size != rect.size
        if sizeChanged {
            barView.frame = NSRect(origin: .zero, size: rect.size)
            setFrame(rect, display: true)
            applyContentScale(for: screen, config: config)
            barView.apply(config: config)
        }
        move(to: rect, animated: isVisible && !sizeChanged && oldTarget?.minX == rect.minX && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    private func applyContentScale(for screen: NSScreen, config: BarConfig) {
        let scale = Self.contentScale(for: screen, config: config)
        barView.bounds = NSRect(x: 0, y: 0, width: max(1, frame.width / scale), height: max(1, frame.height / scale))
        barView.needsLayout = true
    }

    /// Calibrate each display independently; external displays retain readable
    /// logical dimensions instead of inheriting a laptop's small notch height.
    private static func contentScale(for screen: NSScreen, config: BarConfig) -> CGFloat {
        let physical = CGDisplayScreenSize(screen.displayID)
        let target = DisplaySizing.notchTarget(notchPoints: screen.safeAreaInsets.top,
            screenPointHeight: screen.frame.height, screenMillimeterHeight: physical.height)
        return DisplaySizing.readableScale(logicalHeight: config.height,
            physicalHeight: target ?? config.physicalHeightMillimeters,
            screenPoints: screen.frame.size, screenMillimeters: physical,
            isBuiltIn: CGDisplayIsBuiltin(screen.displayID) != 0, multiplier: config.sizeMultiplier)
    }

    private static func frame(for screen: NSScreen, config: BarConfig, avoidingMenuBar: Bool, menuBarHeight: CGFloat) -> NSRect {
        let frame = screen.frame
        let scale = contentScale(for: screen, config: config)
        let totalHeight = config.height * scale + config.coveEdgeDepth
        // Keep notch-aware layout at the physical edge while the menu is hidden.
        // When macOS reveals its menu, make room below it in screen points;
        // the system menu height does not scale with the user's bar size.
        let clearance = avoidingMenuBar ? menuBarHeight : 0
        let y = frame.maxY - totalHeight - clearance - config.topInset * scale
        return NSRect(x: frame.minX, y: y, width: frame.width, height: totalHeight)
    }
}

/// Capture OS inputs once per tick. Tests supply these inputs to the same
/// window update path without moving the user's pointer or changing macOS settings.
struct MenuBarEnvironment {
    var pointer: NSPoint
    var visible: Bool
    var uptime: TimeInterval
    var height: CGFloat

    static func capture(on screen: NSScreen) -> MenuBarEnvironment {
        MenuBarEnvironment(pointer: NSEvent.mouseLocation,
            visible: MenuBarVisibilityDetector.isVisible(on: screen),
            uptime: ProcessInfo.processInfo.systemUptime,
            height: max(NSStatusBar.system.thickness, screen.safeAreaInsets.top, screen.frame.maxY - screen.visibleFrame.maxY))
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
    private static func overlapRatio(_ window: CGRect, display: CGRect) -> CGFloat {
        let intersection = window.intersection(display)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height / max(1, display.width * display.height)
    }

    /// Fullscreen windows normally match the display exactly, but the Window
    /// Server can report a one-pixel inset or a slightly stale frame while a
    /// Space is changing. A nearly full display is a safe geometric fallback;
    /// maximized windows remain below this threshold and are not hidden.
    static func isFullscreenCandidate(_ window: CGRect, display: CGRect, nativeState: Bool?) -> Bool {
        if nativeState == true { return overlapRatio(window, display: display) >= 0.90 }
        guard nativeState != false else { return false }
        return covers(window, display: display) || overlapRatio(window, display: display) >= 0.99
    }

    private static func nativeFullscreen(pid: pid_t, display: CGRect) -> Bool? {
        if pid == ProcessInfo.processInfo.processIdentifier {
            return NSApp.windows.contains {
                $0.styleMask.contains(.fullScreen) &&
                overlapRatio($0.frame, display: display) >= 0.99
            }
        }
        guard pid > 0, AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.05)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &raw) == .success,
              let windows = raw as? [AXUIElement] else { return nil }
        var explicitState: Bool?
        for window in windows {
            var positionValue: CFTypeRef?, sizeValue: CFTypeRef?, fullValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
                  AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
                  let positionValue, let sizeValue,
                  CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { continue }
            var position = CGPoint.zero, size = CGSize.zero
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
            if AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullValue) == .success {
                guard let value = fullValue as? Bool else { continue }
                let axBounds = CGRect(origin: position, size: size)
                guard overlapRatio(axBounds, display: display) >= 0.90 else { continue }
                explicitState = explicitState == true ? true : value
                if value { return true }
            }
        }
        return explicitState
    }

    static func coveredDisplays() -> Set<CGDirectDisplayID> {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        var covered = Set<CGDirectDisplayID>()
        for window in info {
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            if ["Window Server", "Dock"].contains(owner) { continue }
            guard (window[kCGWindowLayer as String] as? Int ?? 0) == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"], let w = bounds["Width"], let h = bounds["Height"] else { continue }
            let rect = CGRect(x: x, y: y, width: w, height: h)
            let matching = NSScreen.screens.filter { screen in
                let display = CGDisplayBounds(screen.displayID)
                let nativeState = nativeFullscreen(pid: window[kCGWindowOwnerPID as String] as? pid_t ?? 0, display: display)
                return isFullscreenCandidate(rect, display: display, nativeState: nativeState)
            }
            guard !matching.isEmpty else { continue }
            matching.forEach { covered.insert($0.displayID) }
        }
        return covered
    }
}

/// Reject missing or implausible EDID measurements instead of magnifying the
/// bar using bad monitor metadata. Both axes must describe the same panel.
enum DisplaySizing {
    static func readableScale(logicalHeight: CGFloat, physicalHeight: CGFloat,
                              screenPoints: CGSize, screenMillimeters: CGSize,
                              isBuiltIn: Bool, multiplier: Double = 1) -> CGFloat {
        let physical = scale(logicalHeight: logicalHeight, physicalHeight: physicalHeight,
            screenPoints: screenPoints, screenMillimeters: screenMillimeters)
        return (isBuiltIn ? physical : max(1, physical)) * CGFloat(multiplier)
    }

    static func notchTarget(notchPoints: CGFloat, screenPointHeight: CGFloat,
                            screenMillimeterHeight: CGFloat) -> CGFloat? {
        guard notchPoints > 0, screenPointHeight > 0,
              (70...2000).contains(screenMillimeterHeight) else { return nil }
        let notchMillimeters = notchPoints / screenPointHeight * screenMillimeterHeight
        guard (3...12).contains(notchMillimeters) else { return nil }
        return notchMillimeters + 1
    }

    static func scale(logicalHeight: CGFloat, physicalHeight: CGFloat,
                      screenPoints: CGSize, screenMillimeters: CGSize) -> CGFloat {
        guard screenPoints.width > 0, screenPoints.height > 0,
              (100...3000).contains(screenMillimeters.width), (70...2000).contains(screenMillimeters.height) else { return 1 }
        let x = screenPoints.width / screenMillimeters.width
        let y = screenPoints.height / screenMillimeters.height
        guard (0.8...1.25).contains(x / y), (1...20).contains(y), logicalHeight > 0 else { return 1 }
        return physicalHeight * y / logicalHeight
    }
}
