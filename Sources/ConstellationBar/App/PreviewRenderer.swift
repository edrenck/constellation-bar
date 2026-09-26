import AppKit

/// Native renderer snapshots, including every appearance/layout and a camera exclusion.
enum PreviewRenderer {
    static func render(to directory: URL) throws {
        ModernControlView.rendersOpaqueMaterials = true
        defer { ModernControlView.rendersOpaqueMaterials = false }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try exportThemeCatalog(to: directory.appendingPathComponent("theme-catalog.json"))
        for style in BarAppearance.allCases {
            for mode in style.isNative ? ["light", "dark"] : ["light"] {
                var config = BarConfig.default
                config.appearance = style
                config.themeMode = mode
                config.rightWidgets = [.agentStatus, .system, .battery, .dateTime]
                config.weather.locationLabel = "Preview"
                config.widgetPreferences.cpuShowsGraph = false
                config.weather.unit = .celsius
                let prefix = "\(style.rawValue)-\(mode)"
                for layout in BarLayout.allCases {
                    config.layout = layout
                    config.barPresentation = layout == .rail ? .fullWidth : .floating
                    for width in [640, 1440] {
                        let content = backdrop(size: NSSize(width: width, height: 90))
                        let bar = BarRootView(frame: NSRect(x: 0, y: 22, width: width, height: 46), config: renderConfig(config))
                        content.addSubview(bar)
                        bar.render(state: state)
                        try capture(content, to: directory.appendingPathComponent("\(prefix)-\(layout.rawValue)-\(width).png"))
                    }
                }
                config.layout = .rail
                config.barPresentation = .fullWidth
                let notch = backdrop(size: NSSize(width: 1440, height: 90))
                let notchedBar = BarRootView(frame: NSRect(x: 0, y: 44, width: 1440, height: 46), config: renderConfig(config))
                notchedBar.previewTopAttached = true
                notchedBar.previewExclusion = 630...810
                notch.addSubview(notchedBar)
                notchedBar.render(state: state)
                let camera = NSView(frame: NSRect(x: 630, y: 61, width: 180, height: 29))
                camera.wantsLayer = true; camera.layer?.backgroundColor = NSColor.black.cgColor
                camera.layer?.cornerRadius = 12; notch.addSubview(camera)
                try capture(notch, to: directory.appendingPathComponent("\(prefix)-notch.png"))
                try renderBoard(config: config, to: directory.appendingPathComponent("\(prefix)-board.png"))
            }
        }
        for scheme in TypesetScheme.allCases {
            for variant in scheme.variants {
                var config = BarConfig.default
                config.appearance = .typeset
                config.typesetScheme = scheme; config.typesetVariant = variant
                config.rightWidgets = [.agentStatus, .system, .battery, .dateTime]
                try renderBoard(config: config, to: directory.appendingPathComponent("typeset-\(scheme.rawValue)-\(variant)-board.png"))
            }
        }
        for centered in [false, true] {
            for notched in [false, true] {
                var config = BarConfig.default
                config.appearance = .cove; config.layout = .rail
                config.visualPreferences.coveScreenBorder = true
                config.widgetPlacement = centered ? .centered : .trailing
                config.rightWidgets = [.agentStatus, .battery, .dateTime]
                let content = backdrop(size: NSSize(width: 1440, height: 130))
                let bar = BarRootView(frame: NSRect(x: 0, y: 64, width: 1440, height: config.height + config.coveEdgeDepth), config: renderConfig(config))
                bar.previewTopAttached = true
                if notched { bar.previewExclusion = 630...810 }
                content.addSubview(bar); bar.render(state: state)
                try capture(content, to: directory.appendingPathComponent("cove-border-\(centered ? "centered" : "edges")-\(notched ? "notch" : "plain").png"))
            }
        }
        for (kind, appearance) in [(WidgetKind.nowPlaying, BarAppearance.nativeGlass), (.calendar, .porcelain), (.vpn, .cove), (.audio, .nativeStudio), (.system, .typeset), (.agentStatus, .nativeStudio), (.timer, .cove), (.keepAwake, .cove), (.reminders, .porcelain), (.dateTime, .nativeGlass), (.keyboard, .typeset)] {
            var config = BarConfig.default; config.appearance = appearance; config.themeMode = "light"
            config.widgetPreferences.worldClockIdentifiers = ["America/New_York", "Europe/London", "Asia/Tokyo"]
            var sample = state.system
            sample.keyboard = KeyboardState(sources: [KeyboardSource(id: "us", name: "ABC", language: "English"), KeyboardSource(id: "british", name: "British", language: "English")], selectedID: "us")
            sample.timer = CountdownState(duration: 1500, remaining: 1124, running: true)
            sample.keepAwake = KeepAwakeState(active: true, displayAwake: false, remaining: 2840)
            sample.reminders = RemindersState(authorized: true, lists: [ReminderList(id: "work", title: "Work")], items: [ReminderItem(id: "review", title: "Review the release notes", list: "Work", due: Date().addingTimeInterval(3600))], message: "")
            sample.agents.providers = [AgentProviderSnapshot(id: "codex", name: "Codex", tasks: [.init(id: "1", activity: .active, title: "Improve the agent status widget", project: "constellation-bar"), .init(id: "2", activity: .active, title: "Review release checks", project: "website"), .init(id: "3", activity: .idle, title: "Update documentation", project: "constellation-bar")], available: true, message: "Tasks on this Mac · includes waiting", sampledAt: Date())]
            sample.agents.providers.append(AgentProviderSnapshot(id: "codex:remote-preview", name: "Codex", tasks: [.init(id: "4", activity: .active, title: "Run integration tests", project: "service")], available: true, message: "Connected over SSH", sampledAt: Date(), hostName: "Build server"))
            sample.mediaSessions = [MediaSession(id: "appleMusic", providerID: "appleMusic", playback: NowPlayingState(title: "Low Tide", artist: "Mira", isPlaying: true, source: "Apple Music", position: 84, duration: 238), canSeek: true, canSkip: true, album: "Coastal Hours", shuffle: false, repeatMode: .off)]
            sample.audio = AudioState(devices: [AudioDeviceState(id: 1, name: "AirPods Max", isInput: false, volume: 0.62, muted: false, canSetVolume: true, canMute: true), AudioDeviceState(id: 2, name: "MacBook Speakers", isInput: false, volume: 0.5, canSetVolume: true)], outputID: 1)
            sample.vpn = VPNState(connections: [VPNConnection(name: "Surfshark", connected: true, provider: "surfshark", detail: "VPN service · routing details unavailable"), VPNConnection(name: "Tailscale", connected: true, provider: "tailscale", id: "tailscale", detail: "Mesh network · exit node off", peers: ["studio-mac · Online", "build-server · Online"])], available: true)
            let now = Date()
            sample.agenda = AgendaState(authorized: true, message: "", calendars: [CalendarSource(id: "studio", title: "Studio", account: "Apple Calendar")], events: [AgendaEvent(id: "1", calendarID: "studio", title: "Design review", calendar: "Studio", start: now.addingTimeInterval(1200), end: now.addingTimeInterval(3000), allDay: false, location: "Meeting room", meetingURL: nil)], rangeStart: now.addingTimeInterval(-86400), rangeEnd: now.addingTimeInterval(86400))
            sample.topProcesses = [ProcessUsage(name: "WindowServer", cpu: 6.2, memory: 1), ProcessUsage(name: "Browser", cpu: 4.8, memory: 2), ProcessUsage(name: "Terminal", cpu: 1.1, memory: 1)]
            let history = WidgetHistory(cpu: [10, 12, 25, 13, 28, 19, 12, 18], memory: [32, 33, 35, 34, 37, 38, 37, 38], dates: (0..<8).map { now.addingTimeInterval(Double($0 - 7) * 42) })
            let panel = MiniAppPanel(kind: kind, state: sample, config: config, history: history)
            let content = backdrop(size: NSSize(width: panel.preferredSize.width + 80, height: panel.preferredSize.height + 80))
            panel.frame = NSRect(origin: NSPoint(x: 40, y: 40), size: panel.preferredSize)
            content.addSubview(panel)
            try capture(content, to: directory.appendingPathComponent("mini-app-\(kind.rawValue).png"))
        }
        var wide = BarConfig.default
        wide.appearance = .cove; wide.layout = .islands
        wide.barPresentation = .floating
        wide.rightWidgets = [.audio, .system, .battery]
        wide.centerWidgets = [.dateTime, .nowPlaying]
        let wideContent = backdrop(size: NSSize(width: 1720, height: 110))
        let wideBar = BarRootView(frame: NSRect(x: 0, y: 32, width: 1720, height: 46), config: renderConfig(wide))
        wideContent.addSubview(wideBar); wideBar.render(state: state)
        try capture(wideContent, to: directory.appendingPathComponent("wide-center-widgets.png"))
        let settings = ConfigurationWindowController(config: .default, onChange: { _ in })
        settings.window?.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        settings.window?.orderFront(nil)
        for index in ConfigurationWindowController.sectionTitles.indices {
            settings.selectSection(index)
            guard let content = settings.window?.contentView else { continue }
            try writeBitmap(content, to: directory.appendingPathComponent("settings-\(index).png"))
        }
        settings.window?.orderOut(nil)
    }

    private static func exportThemeCatalog(to url: URL) throws {
        var catalog: [String: [String: String]] = [:]
        func record(_ config: BarConfig, key: String) {
            let theme = config.appearance.theme(mode: config.themeMode, scheme: config.typesetScheme, variant: config.typesetVariant)
            func hex(_ color: NSColor, over base: NSColor? = nil) -> String {
                let rgb = color.usingColorSpace(.sRGB) ?? color
                let background = (base ?? theme.background).usingColorSpace(.sRGB) ?? theme.background
                let alpha = base == nil ? 1 : rgb.alphaComponent
                return String(format: "#%02x%02x%02x", Int((rgb.redComponent * alpha + background.redComponent * (1-alpha)) * 255), Int((rgb.greenComponent * alpha + background.greenComponent * (1-alpha)) * 255), Int((rgb.blueComponent * alpha + background.blueComponent * (1-alpha)) * 255))
            }
            catalog[key] = ["background": hex(theme.background), "foreground": hex(theme.foreground), "muted": hex(theme.muted),
                "surface": hex(theme.surface, over: theme.background), "border": hex(theme.muted.withAlphaComponent(0.32), over: theme.background),
                "accent": hex(theme.blue), "accentText": hex(theme.background), "radius": "\(Int(config.appearance.panelRadius))px",
                "font": config.appearance == .typeset ? "'SFMono-Regular', Menlo, Consolas, monospace" : "-apple-system, BlinkMacSystemFont, sans-serif"]
        }
        for appearance in BarAppearance.nativeColors {
            for mode in appearance.isNative ? ["light", "dark"] : ["light"] {
                var config = BarConfig.default; config.appearance = appearance; config.themeMode = mode
                record(config, key: "\(appearance.rawValue)-\(mode)-board")
            }
        }
        for scheme in TypesetScheme.allCases {
            for variant in scheme.variants {
                var config = BarConfig.default; config.appearance = .typeset; config.typesetScheme = scheme; config.typesetVariant = variant
                record(config, key: "typeset-\(scheme.rawValue)-\(variant)-board")
            }
        }
        try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys]).write(to: url)
    }

    private static func renderConfig(_ config: BarConfig) -> BarConfig {
        var rendered = config
        rendered.setWidgetLayout(.legacy(rightWidgets: WidgetKind.consolidated(config.rightWidgets), centerWidgets: config.centerWidgets, placement: config.widgetPlacement))
        return rendered
    }

    private static var state: BarState {
        let terminal = WindowIdentity(id: -1, workspace: "02", appName: "Terminal", bundleID: "com.apple.Terminal", title: "Terminal")
        let finder = WindowIdentity(id: -2, workspace: "01", appName: "Finder", bundleID: "com.apple.finder", title: "Projects")
        var system = ConfigurationPreviewView.previewState.system
        system.cpu = CPUState(usage: 18)
        system.weather = WeatherState(temperature: 22, weatherCode: 1, isDay: true, apparentTemperature: 22, humidity: 31, windSpeed: 8)
        system.battery = BatteryState(percent: 86, isCharging: false, timeRemainingMinutes: 245, powerSource: "Battery")
        return BarState(workspaces: [WorkspaceState(name: "01", isFocused: false, windows: [finder]), WorkspaceState(name: "02", isFocused: true, windows: [terminal]), WorkspaceState(name: "03", isFocused: false, windows: []), WorkspaceState(name: "04", isFocused: false, windows: [])], focusedWindow: terminal, system: system)
    }
    private static func backdrop(size: NSSize) -> NSView {
        let view = NSView(frame: NSRect(origin: .zero, size: size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(hex: 0x7C8996).cgColor
        return view
    }
    private static func renderBoard(config: BarConfig, to url: URL) throws {
        let content = backdrop(size: NSSize(width: 1440, height: 650))
        let suffix = config.appearance.isNative ? "AppKit render · opaque material fallback" : "Native AppKit render"
        let themeName = config.appearance == .typeset ? "Typeset / \(config.typesetScheme.title) / \(config.typesetScheme.variantTitle(config.typesetVariant))" : "Native / \(config.appearance.title)"
        let title = NSTextField(labelWithString: "\(themeName)  ·  \(suffix)")
        title.font = .systemFont(ofSize: 23, weight: .semibold)
        title.textColor = .white
        title.frame = NSRect(x: 24, y: 595, width: 1350, height: 35)
        content.addSubview(title)
        for (index, layout) in BarLayout.allCases.enumerated() {
            var local = config; local.layout = layout
            local.barPresentation = layout == .rail ? .fullWidth : .floating
            let y: CGFloat = index == 0 ? 520 : index == 1 ? 140 : 40
            let label = NSTextField(labelWithString: layout.title)
            label.font = .systemFont(ofSize: 12, weight: .semibold)
            label.textColor = .white
            label.frame = NSRect(x: 24, y: y + 47, width: 100, height: 18)
            content.addSubview(label)
            let bar = BarRootView(frame: NSRect(x: 0, y: y, width: 1440, height: 46), config: renderConfig(local))
            bar.previewTopAttached = true
            content.addSubview(bar); bar.render(state: state)
        }
        var panelState = state.system
        panelState.topProcesses = [ProcessUsage(name: "WindowServer", cpu: 6.2, memory: 1), ProcessUsage(name: "Browser", cpu: 4.8, memory: 2), ProcessUsage(name: "Terminal", cpu: 1.1, memory: 1)]
        let panel = MiniAppPanel(kind: .system, state: panelState, config: config,
            history: WidgetHistory(cpu: [10, 14, 12, 26, 17, 12, 9, 13, 21, 15, 28, 36, 21, 17, 9, 13, 18, 16, 12, 18], dates: (0..<20).map { Date().addingTimeInterval(Double($0 - 19) * 15) }))
        let scale: CGFloat = min(0.60, 320 / panel.preferredSize.height)
        panel.frame = NSRect(x: 1120, y: 185, width: panel.preferredSize.width * scale, height: panel.preferredSize.height * scale)
        panel.bounds = NSRect(origin: .zero, size: panel.preferredSize)
        content.addSubview(panel)
        try capture(content, to: url)
    }
    private static func capture(_ content: NSView, to url: URL) throws {
        let window = NSWindow(contentRect: content.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = content
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderFront(nil)
        window.makeFirstResponder(nil)
        try writeBitmap(content, to: url)
        window.orderOut(nil)
    }
    private static func writeBitmap(_ content: NSView, to url: URL) throws {
        content.layoutSubtreeIfNeeded()
        content.displayIfNeeded()
        CATransaction.flush()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) { try data.write(to: url) }
    }
}
