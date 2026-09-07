import AppKit

final class ConfigurationPreviewView: NSView {
    private var config: BarConfig
    private let bar: BarRootView
    var onWidgetSelection: ((WidgetKind) -> Void)?

    init(config: BarConfig) {
        var previewConfig = config
        previewConfig.sideMargin = 10
        self.config = previewConfig
        bar = BarRootView(frame: .zero, config: previewConfig)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        addSubview(bar)
        bar.onWidgetSelection = { [weak self] kind in self?.onWidgetSelection?(kind) }
        bar.render(state: Self.previewState)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let height = config.height + config.coveEdgeDepth
        bar.frame = NSRect(x: 0, y: bounds.midY - height / 2, width: bounds.width, height: height)
    }

    func apply(config: BarConfig) {
        var previewConfig = config
        previewConfig.sideMargin = 10
        self.config = previewConfig
        bar.apply(config: previewConfig)
        bar.render(state: Self.previewState)
        needsLayout = true
    }

    static let previewState: BarState = {
        let finder = WindowIdentity(id: -1, workspace: "1", appName: "Finder", bundleID: "com.apple.finder", title: "Projects")
        let terminal = WindowIdentity(id: -2, workspace: "1", appName: "Terminal", bundleID: "com.apple.Terminal", title: "Build")
        let music = WindowIdentity(id: -3, workspace: "2", appName: "Music", bundleID: "com.apple.Music", title: "Library")
        var system = SystemState()
        system.agents.providers = [AgentProviderSnapshot(id: "codex", name: "Codex", tasks: [.init(id: "preview", activity: .active)], available: true, message: "Preview")]
        system.date = Date(timeIntervalSince1970: 1788714000)
        system.battery = BatteryState(percent: 72, isCharging: false, timeRemainingMinutes: 245, powerSource: "Battery")
        system.network = NetworkSpeedState(downloadBytesPerSecond: 1_800_000, uploadBytesPerSecond: 240_000)
        system.cpu = CPUState(usage: 34)
        system.memory = MemoryState(usage: 58, usedBytes: 19_000_000_000, totalBytes: 32_000_000_000)
        system.nowPlaying = NowPlayingState(title: "Midnight City", artist: "M83", isPlaying: true, source: "Music")
        system.weather = WeatherState(temperature: 78, weatherCode: 1, isDay: true, apparentTemperature: 79, humidity: 31, windSpeed: 8)
        return BarState(
            workspaces: [
                WorkspaceState(name: "1", isFocused: true, windows: [finder, terminal]),
                WorkspaceState(name: "2", isFocused: false, windows: [music]),
                WorkspaceState(name: "3", isFocused: false, windows: [])
            ],
            focusedWindow: finder,
            system: system
        )
    }()
}
