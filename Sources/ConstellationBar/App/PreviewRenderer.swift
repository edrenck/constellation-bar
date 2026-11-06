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
            sample.timer = CountdownState(duration: 1500, remaining: 1124, phase: .running)
            sample.keepAwake = KeepAwakeState(active: true, displayAwake: false, remaining: 2840)
            sample.reminders = RemindersState(authorized: true, lists: [ReminderList(id: "work", title: "Work")], items: [ReminderItem(id: "review", title: "Review the release notes", list: "Work", due: Date().addingTimeInterval(3600))], message: "")
            sample.agents.providers = [AgentProviderSnapshot(id: "codex", name: "Codex", tasks: [.init(id: "1", activity: .active, title: "Improve the agent status widget", project: "constellation-bar"), .init(id: "2", activity: .active, title: "Review release checks", project: "website"), .init(id: "3", activity: .idle, title: "Update documentation", project: "constellation-bar")], available: true, message: "Tasks on this Mac · includes waiting", sampledAt: Date())]
            sample.agents.providers.append(AgentProviderSnapshot(id: "codex:remote-preview", name: "Codex", tasks: [.init(id: "4", activity: .active, title: "Run integration tests", project: "service")], available: true, message: "Connected over SSH", sampledAt: Date(), hostName: "Build server"))
            sample.mediaSessions = [MediaSession(id: "appleMusic", providerID: "appleMusic", playback: NowPlayingState(title: "Low Tide", artist: "Mira", isPlaying: true, source: "Apple Music", position: 84, duration: 238), canSeek: true, canSkip: true, album: "Coastal Hours", shuffle: false, repeatMode: .off)]
            sample.audio = AudioState(devices: [AudioDeviceState(id: 1, name: "AirPods Max", isInput: false, volume: 0.62, muted: false, canSetVolume: true, canMute: true), AudioDeviceState(id: 2, name: "MacBook Speakers", isInput: false, volume: 0.5, canSetVolume: true)], outputID: 1)
            sample.vpn = VPNState(connections: [VPNConnection(name: "Surfshark", connected: true, provider: "surfshark", detail: "VPN service · routing details unavailable"), VPNConnection(name: "Tailscale", connected: true, provider: "tailscale", id: "tailscale", detail: "Mesh network · exit node off", peers: ["studio-mac · Online", "build-server · Online"])], available: true)
            let now = Date()
            let agendaDate = sample.date
            sample.agenda = AgendaState(authorized: true, message: "", calendars: [CalendarSource(id: "studio", title: "Studio", account: "Apple Calendar")], events: [AgendaEvent(id: "1", calendarID: "studio", title: "Design review", calendar: "Studio", start: agendaDate.addingTimeInterval(1200), end: agendaDate.addingTimeInterval(3000), allDay: false, location: "Meeting room", meetingURL: nil)], rangeStart: Calendar.current.startOfDay(for: agendaDate).addingTimeInterval(-86400), rangeEnd: Calendar.current.startOfDay(for: agendaDate).addingTimeInterval(172800))
            sample.topProcesses = [ProcessUsage(name: "WindowServer", cpu: 6.2, memory: 1), ProcessUsage(name: "Browser", cpu: 4.8, memory: 2), ProcessUsage(name: "Terminal", cpu: 1.1, memory: 1)]
            sample.topProcessesStatus = .available
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
        try renderRecoveryAndCollectionFixtures(to: directory)
        try renderConstrainedFixtures(to: directory)
        try renderSamplingFixtures(to: directory)
        try renderMeasurementFixtures(to: directory)
        try renderDailyFixtures(to: directory)
        try renderCalendarAndFocusFixtures(to: directory)
        try renderReminderSettingsFixtures(to: directory)
        try renderSettingsInteractionFixtures(to: directory)
        try renderFullscreenDiagnosticsFixtures(to: directory)
        try renderPanelTaskPriorityFixtures(to: directory)
        try renderTimerRecoveryFixtures(to: directory)
    }

    private static func renderTimerRecoveryFixtures(to directory: URL) throws {
        let message = "The countdown could not resume. Please try again. " + String(repeating: "Fixture service did not respond; check the connection before retrying. ", count: 20) + "END OF ERROR"
        for style in [BarAppearance.nativeStudio, .cove, .porcelain, .typeset] {
            var config = BarConfig.default; config.appearance = style; config.themeMode = "light"
            for (name, phase) in [("ready", CountdownState.Phase.ready), ("running", .running), ("paused-error", .paused), ("finished", .finished)] {
                var sample = state.system
                sample.timer = CountdownState(duration: 1500, remaining: phase == .finished ? 0 : phase == .ready ? 1500 : 1124, phase: phase)
                let panel = MiniAppPanel(kind: .timer, state: sample, config: config, history: WidgetHistory())
                panel.frame = NSRect(x: 40, y: 40, width: 320, height: 280)
                if phase == .paused { panel.onAction = { _, complete in complete(message) }; panel.perform(.resumeTimer) }
                let content = backdrop(size: NSSize(width: 400, height: 360)); content.addSubview(panel)
                try capture(content, to: directory.appendingPathComponent("timer-recovery-\(style.rawValue)-\(name).png"))
            }
        }
        var config = BarConfig.default; config.appearance = .nativeStudio; config.themeMode = "light"
        let panel = MiniAppPanel(kind: .timer, state: state.system, config: config, history: WidgetHistory())
        let window = BarFloatingPanel(contentRect: NSRect(x: -10000, y: -10000, width: 320, height: 280))
        window.isReleasedWhenClosed = false; window.contentView = panel; window.orderFront(nil)
        defer { window.close() }
        panel.onAction = { _, complete in complete(message) }; panel.perform(.resumeTimer)
        panel.feedbackDetails.performClick(nil)
        if let sheet = window.attachedSheet {
            defer { window.endSheet(sheet); sheet.orderOut(nil) }
            sheet.appearance = NSAppearance(named: .aqua)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.35))
            if let content = sheet.contentView {
                // NSAlert's content view omits its native window background when cached.
                var background = NSColor.windowBackgroundColor.cgColor
                sheet.effectiveAppearance.performAsCurrentDrawingAppearance { background = NSColor.windowBackgroundColor.cgColor }
                try writeBitmap(content, to: directory.appendingPathComponent("timer-recovery-error-details.png"), backgroundColor: background)
            }
        }
    }

    private static func renderPanelTaskPriorityFixtures(to directory: URL) throws {
        func capturePanel(_ panel: MiniAppPanel, name: String, size: NSSize = NSSize(width: 320,height: 280)) throws {
            panel.frame = NSRect(origin: NSPoint(x: 40,y: 40),size: size)
            let content = backdrop(size: NSSize(width: size.width+80,height: size.height+80))
            content.addSubview(panel)
            try capture(content,to: directory.appendingPathComponent(name+".png"))
        }
        var sample = state.system
        sample.mediaSessions = (1...2).map { index in
            MediaSession(id: "source\(index)",providerID: "appleMusic",
                playback: NowPlayingState(title: "Low Tide — Live from the Coastal Sessions",artist: "Mira and the Evening Ensemble",isPlaying: true,source: "Music \(index)",position: 84,duration: 238),canSeek: true,canSkip: true,album: "Coastal Hours — Extended Edition",shuffle: false,repeatMode: .off)
        }
        let start = Calendar.current.startOfDay(for: sample.date)
        sample.agenda = AgendaState(authorized: true,message: "",events: [
            AgendaEvent(id: "review",calendarID: "fixture",title: "Project review",calendar: "Work",start: start.addingTimeInterval(36000),end: start.addingTimeInterval(39600),allDay: false,location: "Meeting room",meetingURL: nil)
        ])
        for appearance in [BarAppearance.nativeStudio,.cove,.porcelain,.typeset] {
            var config = BarConfig.default; config.appearance = appearance; config.themeMode = "light"
            for kind in [WidgetKind.nowPlaying,.calendar] {
                try capturePanel(MiniAppPanel(kind: kind,state: sample,config: config,history: WidgetHistory()),name: "compact-task-\(appearance.rawValue)-\(kind.rawValue)")
            }
        }
        var config = BarConfig.default; config.appearance = .nativeStudio; config.themeMode = "light"
        var permission = SystemState()
        permission.agenda = AgendaState(authorized: false,message: "Allow Calendar access to show appointments synced through macOS Internet Accounts. Your events stay read-only.")
        permission.providerStatuses = [ProviderStatus(id: "appleMusic",message: "Allow Apple Music access to control playback. You can continue using the system Now Playing provider without this access.",needsAttention: true)]
        for kind in [WidgetKind.nowPlaying,.calendar] {
            try capturePanel(MiniAppPanel(kind: kind,state: permission,config: config,history: WidgetHistory()),name: "compact-access-\(kind.rawValue)")
        }
        var empty = SystemState(); empty.agenda = AgendaState(authorized: true,message: "")
        try capturePanel(MiniAppPanel(kind: .calendar,state: empty,config: config,history: WidgetHistory()),name: "compact-calendar-empty")
        sample.topProcesses = [ProcessUsage(name: "WindowServer",cpu: 11,memory: 1),ProcessUsage(name: "Browser",cpu: 5,memory: 2),ProcessUsage(name: "Terminal",cpu: 1,memory: 1)]
        sample.topProcessesStatus = .available
        let system = MiniAppPanel(kind: .system,state: sample,config: config,history: WidgetHistory())
        func buttons() -> [WidgetActionButton] {
            func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0]+descendants($0) } }
            return descendants(system.stack).compactMap { $0 as? WidgetActionButton }
        }
        buttons().first { $0.identifier?.rawValue == "system.processSort" }?.performClick(nil)
        try capturePanel(system,name: "system-process-ascending",size: system.preferredSize)
        buttons().first { $0.title == "NETWORK" }?.performClick(nil)
        try capturePanel(system,name: "system-network-controls",size: system.preferredSize)
    }

    private static func renderFullscreenDiagnosticsFixtures(to directory: URL) throws {
        for available in [false, true] {
            var config = BarConfig.default; config.displayMode = .allDisplays
            let diagnostics = IntegrationDiagnostics()
            diagnostics.fullscreen = FullscreenDetector.snapshot(NSScreen.screens.map(\.displayID)) { _ in available ? 0 : nil }
            let settings = ConfigurationWindowController(config: config, diagnostics: diagnostics, onChange: { _ in })
            defer { settings.close() }
            settings.window?.setFrameOrigin(NSPoint(x: -10000,y: -10000)); settings.window?.orderFront(nil)
            settings.selectSection(4)
            if let content = settings.window?.contentView {
                try writeBitmap(content, to: directory.appendingPathComponent("settings-fullscreen-\(available ? "recovered" : "unavailable").png"))
            }
        }
    }

    private static func renderSettingsInteractionFixtures(to directory: URL) throws {
        for index in ConfigurationWindowController.sectionTitles.indices {
            let runtime = WidgetRuntime(services: WidgetServices(reminders: RemindersProvider(reader: PreviewReminderListReader(snapshot: ReminderListSnapshot(), fails: false))))
            let settings = ConfigurationWindowController(config: .default, widgets: runtime, onChange: { _ in })
            defer { settings.close(); runtime.stop() }
            settings.window?.setContentSize(NSSize(width: 640,height: 420))
            settings.window?.setFrameOrigin(NSPoint(x: -10000,y: -10000)); settings.window?.orderFront(nil)
            settings.selectSection(index)
            if let content = settings.window?.contentView {
                try writeBitmap(content, to: directory.appendingPathComponent("settings-compact-\(index).png"))
            }
        }
        let recovery = ConfigurationWindowController(config: .default,
            persist: { _ in .failed("The configuration is read-only. Restore write access and retry, or revert to your saved settings.") }, onChange: { _ in })
        defer { recovery.close() }
        recovery.config.height += 1; recovery.commit(); recovery.selectSection(0)
        if let content = recovery.window?.contentView { try writeBitmap(content, to: directory.appendingPathComponent("settings-wide-recovery.png")) }

        var config = BarConfig.default
        config.setWidgetLayout(WidgetZoneLayout(left: [.widget(.timer), .widget(.dateTime), .widget(.reminders)], center: [], right: []))
        let arranged = ConfigurationWindowController(config: config, onChange: { _ in })
        defer { arranged.close() }
        arranged.window?.setFrameOrigin(NSPoint(x: -10000,y: -10000)); arranged.window?.orderFront(nil); arranged.selectSection(1)
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        if let button = descendants(arranged.widgetEditor).compactMap({ $0 as? NSButton }).first(where: { $0.accessibilityLabel() == "Move Reminders earlier" }) {
            arranged.window?.makeFirstResponder(button)
            if let action = button.action { _ = button.sendAction(action, to: button.target) }
        }
        if let content = arranged.window?.contentView { try writeBitmap(content, to: directory.appendingPathComponent("settings-widget-reordered.png")) }
    }

    private static func renderReminderSettingsFixtures(to directory: URL) throws {
        for name in ["lists", "unavailable", "permission", "empty", "error"] {
            let lists = name == "empty" ? [] : [ReminderList(id: "work", title: "Work"), ReminderList(id: "personal", title: "Personal")]
            let reader = PreviewReminderListReader(snapshot: ReminderListSnapshot(authorized: name != "permission", lists: lists), fails: name == "error")
            let runtime = WidgetRuntime(services: WidgetServices(reminders: RemindersProvider(reader: reader)))
            var config = BarConfig.default; config.widgetPreferences.reminderListIDs = name == "unavailable" ? ["removed", "work"] : ["work"]
            if name == "empty" || name == "permission" { config.widgetPreferences.reminderListIDs = [] }
            let settings = ConfigurationWindowController(config: config, widgets: runtime, onChange: { _ in })
            defer { settings.close(); runtime.stop() }
            settings.window?.setFrameOrigin(NSPoint(x: -10000, y: -10000)); settings.window?.orderFront(nil)
            let deadline = Date(timeIntervalSinceNow: 2)
            while settings.reminderListChoices.isLoading, Date() < deadline {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            }
            guard !settings.reminderListChoices.isLoading else { throw WidgetActionError(message: "Reminder settings fixture did not complete") }
            settings.selectWidgetOptions(.widget(.reminders))
            if let content = settings.window?.contentView {
                try writeBitmap(content, to: directory.appendingPathComponent("settings-reminders-\(name).png"))
            }
        }
    }

    private static func renderCalendarAndFocusFixtures(to directory: URL) throws {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5))!
        var config = BarConfig.default; config.appearance = .nativeStudio; config.themeMode = "light"
        for name in ["calendar-all-day", "calendar-all-day-span", "calendar-overnight", "timer-keyboard-focus"] {
            var sample = state.system; sample.date = start.addingTimeInterval(12*3600)
            let days = name.hasSuffix("span") ? 3 : 1
            let eventStart = name.hasSuffix("overnight") ? start.addingTimeInterval(23*3600) : start
            let eventEnd = name.hasSuffix("overnight") ? eventStart.addingTimeInterval(7200) : calendar.date(byAdding: .day, value: days, to: start)!.addingTimeInterval(-1)
            sample.agenda = AgendaState(authorized: true, message: "", events: [AgendaEvent(id: "fixture", calendarID: "fixture", title: name.hasSuffix("overnight") ? "Late review" : "Planning day", calendar: "Fixture", start: eventStart, end: eventEnd, allDay: !name.hasSuffix("overnight"), location: "", meetingURL: nil)])
            sample.timer = CountdownState(duration: 60, remaining: 40, phase: .paused)
            let panel = MiniAppPanel(kind: name.hasPrefix("timer") ? .timer : .calendar, state: sample, config: config, history: WidgetHistory())
            panel.frame = NSRect(origin: NSPoint(x: 40,y: 40), size: panel.preferredSize)
            let content = backdrop(size: NSSize(width: panel.preferredSize.width+80,height: panel.preferredSize.height+80)); content.addSubview(panel)
            let focus = name.hasPrefix("timer") ? panel.stack.arrangedSubviews.flatMap { $0.subviews }.first { $0.identifier?.rawValue == "timer.primary" } : nil
            try capture(content, to: directory.appendingPathComponent(name+".png"), focusedControl: focus)
        }
    }

    private static func renderDailyFixtures(to directory: URL) throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Phoenix")!
        let components = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 11, day: 5)
        let start = calendar.date(from: components)!
        let items = [ReminderItem(id: "day", title: "Review the release notes", list: "Work", dueComponents: components),
                     ReminderItem(id: "time", title: "Morning check-in", list: "Work", due: start.addingTimeInterval(9*3600))]
        for name in ["reminders-date-only", "reminders-date-only-overdue", "timer-last-second", "timer-finished", "awake-display-active", "awake-display-failure"] {
            var config = BarConfig.default; config.appearance = name.hasPrefix("awake") ? .cove : .nativeStudio; config.themeMode = "light"
            var sample = state.system; sample.date = start.addingTimeInterval(name.hasSuffix("overdue") ? 36*3600 : 12*3600)
            sample.reminders = RemindersState(authorized: true, items: items, message: "")
            sample.timer = CountdownState(duration: 60, remaining: name == "timer-finished" ? 0 : 0.2, phase: name == "timer-finished" ? .finished : .running)
            sample.keepAwake = KeepAwakeState(active: true, displayAwake: name == "awake-display-active", remaining: 45.2)
            let kind: WidgetKind = name.hasPrefix("reminders") ? .reminders : name.hasPrefix("timer") ? .timer : .keepAwake
            let panel = MiniAppPanel(kind: kind, state: sample, config: config, history: WidgetHistory())
            if name.hasSuffix("failure") {
                panel.onAction = { _, complete in complete("macOS could not change the display mode. Your existing session and its end time are unchanged. Try again.") }
                panel.perform(.keepAwakeDisplay(true))
            }
            panel.frame = NSRect(origin: NSPoint(x: 40, y: 40), size: panel.preferredSize)
            let content = backdrop(size: NSSize(width: panel.preferredSize.width+80, height: panel.preferredSize.height+80)); content.addSubview(panel)
            try capture(content, to: directory.appendingPathComponent(name+".png"))
        }
    }

    private static func renderMeasurementFixtures(to directory: URL) throws {
        var config = BarConfig.default; config.appearance = .nativeStudio; config.themeMode = "light"
        let message = "This measurement could not be read. The next sample retries automatically."
        for name in ["memory-unavailable", "network-unavailable", "processes-unavailable", "audio-unavailable", "audio-partial"] {
            var sample = state.system
            sample.memory = MemoryState(usage: 0, status: .failed(message)); sample.network = NetworkSpeedState(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0, status: .failed(message))
            sample.topProcessesStatus = .failed("Process list could not be read completely. Retrying with the next sample.")
            sample.audio = AudioState(status: .failed("Read audio device list failed (Core Audio -50). Retry or open Sound settings."))
            if name == "audio-partial" {
                sample.audio = AudioState(devices: [AudioDeviceState(id: 1, name: "Fixture Speakers", isInput: false, issues: ["Read audio volume failed (Core Audio -50). Retry or open Sound settings.", "Read audio mute status failed (Core Audio -50). Retry or open Sound settings."])], outputID: 1)
            }
            let kind: WidgetKind = name.hasPrefix("audio") ? .audio : name.hasPrefix("memory") ? .memory : .system
            let panel = MiniAppPanel(kind: kind, state: sample, config: config, history: WidgetHistory())
            if name.hasPrefix("network") {
                let network = panel.stack.arrangedSubviews.compactMap { $0 as? NSStackView }.flatMap(\.arrangedSubviews).compactMap { $0 as? WidgetActionButton }.first { $0.title == "NETWORK" }
                network?.performClick(nil)
            }
            panel.frame = NSRect(origin: NSPoint(x: 40, y: 40), size: panel.preferredSize)
            let content = backdrop(size: NSSize(width: panel.preferredSize.width+80, height: panel.preferredSize.height+80)); content.addSubview(panel)
            try capture(content, to: directory.appendingPathComponent(name+".png"))
        }
        var sample = state.system; sample.disk = DiskState(usage: 0, status: .failed("Disk capacity could not be read. The next sample retries automatically. Open system settings if this continues."))
        let disk = WidgetInspectorView(kind: .disk, state: sample, config: config, pinned: true)
        disk.frame = NSRect(origin: NSPoint(x: 40, y: 40), size: disk.preferredSize)
        let content = backdrop(size: NSSize(width: disk.preferredSize.width+80, height: disk.preferredSize.height+80)); content.addSubview(disk)
        try capture(content, to: directory.appendingPathComponent("disk-unavailable.png"))
    }

    private static func renderSamplingFixtures(to directory: URL) throws {
        var config = BarConfig.default; config.appearance = .nativeStudio; config.themeMode = "light"
        for (name, kind, cpu) in [("system-cpu-unavailable", WidgetKind.system, CPUState(usage: 0, status: .failed("CPU sampling failed (macOS error 5). Retrying with the next sample."))), ("system-cpu-waiting", .system, CPUState(usage: 0, status: .waiting)), ("vpn-unavailable", .vpn, CPUState(usage: 18))] {
            var sample = state.system; sample.cpu = cpu
            sample.vpn = VPNState(message: "macOS VPN status returned incomplete output. Retry or open VPN settings.")
            let panel = MiniAppPanel(kind: kind, state: sample, config: config, history: WidgetHistory())
            panel.frame = NSRect(origin: NSPoint(x: 40, y: 40), size: panel.preferredSize)
            let content = backdrop(size: NSSize(width: panel.preferredSize.width+80, height: panel.preferredSize.height+80)); content.addSubview(panel)
            try capture(content, to: directory.appendingPathComponent(name+".png"))
        }
    }

    private static func renderConstrainedFixtures(to directory: URL) throws {
        var config = BarConfig.default; config.appearance = .nativeStudio; config.themeMode = "light"
        config.weather.latitude = 0; config.weather.longitude = 0; config.weather.locationLabel = "Preview"
        for kind in WidgetKind.selectableCases where MiniAppPanel.kinds.contains(kind) {
            var sample = state.system
            let now = sample.date
            sample.weather.fetchedAt = now; sample.weather.age = 0
            sample.mediaSessions = [MediaSession(id: "fixture", providerID: "appleMusic", playback: NowPlayingState(title: "Low Tide", artist: "Mira", isPlaying: true, source: "Apple Music", position: 84, duration: 238), canSeek: true, canSkip: true, album: "Coastal Hours", shuffle: false, repeatMode: .off)]
            sample.audio = AudioState(devices: [AudioDeviceState(id: 1, name: "AirPods Max", isInput: false, volume: 0.62, muted: false, canSetVolume: true, canMute: true), AudioDeviceState(id: 2, name: "MacBook Speakers", isInput: false, volume: 0.5, canSetVolume: true)], outputID: 1)
            sample.vpn = VPNState(connections: [VPNConnection(name: "Tailscale", connected: true, provider: "tailscale", id: "fixture", detail: "Mesh network · exit node off", peers: ["studio-mac · Online", "build-server · Offline"])], available: true)
            sample.keyboard = KeyboardState(sources: [KeyboardSource(id: "us", name: "ABC", language: "English"), KeyboardSource(id: "british", name: "British", language: "English")], selectedID: "us")
            sample.reminders = RemindersState(authorized: true, items: [ReminderItem(id: "fixture", title: "Review the release notes", list: "Work", due: now)], message: "")
            sample.agents.providers = [AgentProviderSnapshot(id: "fixture", name: "Codex", tasks: [.init(id: "task", activity: .active, title: "Review release checks", project: "Fixture")], available: true, message: "Connected", sampledAt: now)]
            sample.agenda = AgendaState(authorized: true, message: "", calendars: [CalendarSource(id: "fixture", title: "Fixture", account: "Local")], events: (1...5).map {
                AgendaEvent(id: "\($0)", calendarID: "fixture", title: "Project \($0) review", calendar: "Fixture", start: now.addingTimeInterval(1200), end: now.addingTimeInterval(3000), allDay: false, location: "Meeting room", meetingURL: nil)
            })
            let panel = MiniAppPanel(kind: kind, state: sample, config: config, history: WidgetHistory())
            panel.frame = NSRect(x: 40, y: 40, width: 320, height: 280)
            let content = backdrop(size: NSSize(width: 400, height: 360)); content.addSubview(panel)
            try capture(content, to: directory.appendingPathComponent("constrained-\(kind.rawValue).png"))
        }
        let errorPanel = MiniAppPanel(kind: .timer, state: SystemState(), config: config, history: WidgetHistory())
        errorPanel.frame = NSRect(x: 40, y: 40, width: 320, height: 280)
        errorPanel.onAction = { _, complete in complete("The device could not complete this action. Check that it is connected, open its settings, then retry. Your previous selection is still active.") }
        errorPanel.perform(.startTimer(seconds: 60))
        let content = backdrop(size: NSSize(width: 400, height: 360)); content.addSubview(errorPanel)
        try capture(content, to: directory.appendingPathComponent("constrained-action-error.png"))
        let settings = ConfigurationWindowController(config: .default, persist: { _ in .failed("Configuration is read-only. Choose Retry after restoring access, or Revert to your saved settings.") }) { _ in }
        settings.window?.setContentSize(NSSize(width: 640, height: 420))
        settings.config.height += 2; settings.commit(); settings.selectSection(2)
        if let content = settings.window?.contentView { try writeBitmap(content, to: directory.appendingPathComponent("settings-constrained-recovery.png")) }
        settings.close()
    }

    private static func renderRecoveryAndCollectionFixtures(to directory: URL) throws {
        let windows = (1...25).map { WindowIdentity(id: $0, workspace: "dev", appName: "Terminal", bundleID: "com.apple.Terminal", title: "Project \($0) · Development session") }
        let workspace = WorkspaceState(name: "dev", isFocused: true, windows: windows)
        var config = BarConfig.default; config.themeMode = "dark"
        let overview = WorkspaceOverviewView(workspace: workspace, theme: config.theme)
        let switcher = WindowSwitcherView(windows: windows, focusedID: 25, theme: config.theme)
        for (name, panel, size) in [("workspace-many-windows", overview as WindowCollectionPanel, overview.preferredSize),
                                    ("window-switcher-many-windows", switcher, switcher.preferredSize),
                                    ("workspace-narrow-windows", WorkspaceOverviewView(workspace: workspace, theme: config.theme), NSSize(width: 220, height: 240))] {
            let content = backdrop(size: NSSize(width: size.width + 80, height: size.height + 80))
            panel.frame = NSRect(origin: NSPoint(x: 40, y: 40), size: size)
            content.addSubview(panel)
            try capture(content, to: directory.appendingPathComponent(name + ".png"))
        }
        config.appearance = .nativeStudio; config.themeMode = "light"
        let now = Date()
        let item = ReminderItem(id: "fixture", title: "Review the release notes", list: "Work", due: now.addingTimeInterval(-3600))
        let reminders: [(String, RemindersState)] = [
            ("unavailable", RemindersState(authorized: true, message: "", failure: "Reminders did not respond.", nextAttemptAt: now.addingTimeInterval(15))),
            ("saved", RemindersState(authorized: true, items: [item], message: "", fetchedAt: now.addingTimeInterval(-120), failure: "Reminders did not respond.", nextAttemptAt: now.addingTimeInterval(15))),
            ("expired", RemindersState(authorized: true, message: "", fetchedAt: now.addingTimeInterval(-360), failure: "Reminders did not respond.", nextAttemptAt: now.addingTimeInterval(15), isExpired: true)),
            ("permission", RemindersState())
        ]
        for (name, reminderState) in reminders {
            var sample = state.system; sample.date = now; sample.reminders = reminderState
            let panel = MiniAppPanel(kind: .reminders, state: sample, config: config, history: WidgetHistory())
            let content = backdrop(size: NSSize(width: panel.preferredSize.width + 80, height: panel.preferredSize.height + 80))
            panel.frame = NSRect(origin: NSPoint(x: 40, y: 40), size: panel.preferredSize)
            content.addSubview(panel)
            try capture(content, to: directory.appendingPathComponent("reminders-\(name).png"))
        }
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
    private static func capture(_ content: NSView, to url: URL, focusedControl: NSView? = nil) throws {
        let window = NSWindow(contentRect: content.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = content
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderFront(nil)
        window.makeFirstResponder(focusedControl)
        try writeBitmap(content, to: url)
        window.orderOut(nil)
    }
    private static func writeBitmap(_ content: NSView, to url: URL, backgroundColor: CGColor? = nil) throws {
        content.layoutSubtreeIfNeeded()
        content.displayIfNeeded()
        CATransaction.flush()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        var output = bitmap
        if let backgroundColor {
            guard let original = bitmap.cgImage,
                  let context = CGContext(data: nil, width: bitmap.pixelsWide, height: bitmap.pixelsHigh, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw WidgetActionError(message: "Could not create an opaque native fixture.")
            }
            let rect = CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
            context.setFillColor(backgroundColor); context.fill(rect); context.draw(original, in: rect)
            guard let image = context.makeImage() else { throw WidgetActionError(message: "Could not export an opaque native fixture.") }
            output = NSBitmapImageRep(cgImage: image)
        }
        if let data = output.representation(using: .png, properties: [:]) { try data.write(to: url) }
    }
}

private final class PreviewReminderListReader: RemindersReading {
    let snapshot: ReminderListSnapshot
    let fails: Bool
    init(snapshot: ReminderListSnapshot, fails: Bool) { self.snapshot = snapshot; self.fails = fails }
    var isAuthorized: Bool { snapshot.authorized }
    func readLists() throws -> [ReminderList] {
        if fails { throw WidgetActionError(message: "The list service did not respond.") }
        return snapshot.lists
    }
    func read(listIDs: [String], now: Date) -> RemindersState { RemindersState(authorized: snapshot.authorized, lists: snapshot.lists, message: "") }
    func requestAccess(completion: @escaping (String?) -> Void) { completion("Preview fixtures do not request permissions.") }
}
