import AppKit
import CoreAudio

private final class WidgetSlider: NSSlider {
    var handler: ((Double) -> Void)?
    convenience init(value: Double, max: Double, label: String, handler: @escaping (Double) -> Void) {
        self.init(value: value, minValue: 0, maxValue: max, target: nil, action: nil)
        self.handler = handler; target = self; action = #selector(changed)
        isContinuous = false; setAccessibilityLabel(label)
    }
    @objc private func changed() { handler?(doubleValue) }
}
private final class PanelDocument: NSView { override var isFlipped: Bool { true } }

/// Layouts follow the approved mini-app boards, while adapters own data and capabilities.
final class MiniAppPanel: OverlayContentView, NSSearchFieldDelegate {
    static let kinds: Set<WidgetKind> = [.nowPlaying, .calendar, .vpn, .audio, .system, .cpu, .memory, .agentStatus]
    private let kind: WidgetKind
    private let config: BarConfig
    private var state: SystemState
    private var history: WidgetHistory
    private let scroll = NSScrollView()
    private let document = PanelDocument()
    private let stack = NSStackView()
    private let heading = NSTextField(labelWithString: "")
    private let headerIcon = PanelGlyph()
    private let headerLine = NSBox()
    private let status = NSTextField(wrappingLabelWithString: "")
    private var closeControl: WidgetActionButton!
    private var pinControl: WidgetActionButton!
    private var pinned = true
    private var refreshers: [() -> Void] = []
    private var signature = ""
    private var selectedSession = ""
    private var selectedTab = 0
    private var mediaTab = 0
    private var rangeSeconds: Double = 300
    private var day = Calendar.current.startOfDay(for: Date())
    private var calendarChooser = false
    private var selectedVPN = ""
    private var peerQuery = ""
    private var peerContainer: NSStackView?
    private var currentPeers: [String] = []
    private var selectedEvent: String?
    private var hiddenCalendars = Set(UserDefaults.standard.stringArray(forKey: "hiddenWidgetCalendars") ?? [])
    private var busy = false
    var onAction: ((WidgetAction, @escaping (String?) -> Void) -> Void)?
    var onClose: (() -> Void)?
    var onOpenAudio: (() -> Void)?
    var onPinChange: ((Bool) -> Void)?
    var preferredSize: NSSize {
        switch kind {
        case .agentStatus: return NSSize(width: 440, height: 430)
        case .calendar: return NSSize(width: 620, height: 530)
        case .nowPlaying: return NSSize(width: 440, height: 550)
        case .vpn: return NSSize(width: 480, height: 540)
        case .audio: return NSSize(width: 420, height: 490)
        default: return NSSize(width: 460, height: 540)
        }
    }
    private var bodyWidth: CGFloat { preferredSize.width - 40 }
    init(kind: WidgetKind, state: SystemState, config: BarConfig, history: WidgetHistory) {
        self.kind = kind; self.state = state; self.config = config; self.history = history
        super.init(frame: .zero)
        if kind == .memory { selectedTab = 1 }
        applyAppearance(theme: config.theme)
        heading.stringValue = kind == .nowPlaying ? "Music" : kind == .vpn ? "VPN & tunnels" : [.cpu, .memory, .system].contains(kind) ? "System" : kind.menuTitle
        heading.font = config.appearance.font(size: 14, weight: .semibold); heading.textColor = config.theme.foreground
        addSubview(heading)
        headerIcon.image = NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: nil)
        headerIcon.color = config.theme.foreground; headerIcon.tile = config.theme.surfaceStrong
        addSubview(headerIcon)
        closeControl = iconButton("xmark", label: "Close panel", size: 15) { [weak self] in self?.onClose?() }
        pinControl = iconButton("pin.fill", label: "Unpin panel", size: 14) { [weak self] in
            guard let self else { return }
            self.setPinned(!self.pinned)
            self.onPinChange?(self.pinned)
        }
        addSubview(closeControl); addSubview(pinControl)
        headerLine.boxType = .separator; addSubview(headerLine)
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.documentView = document; addSubview(scroll)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = [.system, .cpu, .memory].contains(kind) ? 8 : 14
        stack.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: document.leadingAnchor), stack.topAnchor.constraint(equalTo: document.topAnchor), stack.widthAnchor.constraint(equalToConstant: bodyWidth)])
        status.font = config.appearance.font(size: 10); status.textColor = config.theme.muted; addSubview(status)
        rebuild()
    }
    required init?(coder: NSCoder) { fatalError() }
    func setPinned(_ pinned: Bool) {
        self.pinned = pinned
        pinControl.symbolName = pinned ? "pin.fill" : "pin"
        pinControl.setAccessibilityLabel(pinned ? "Unpin panel" : "Pin panel")
        pinControl.toolTip = pinned ? "Unpin panel" : "Pin panel"
    }
    override func layout() {
        super.layout()
        headerIcon.frame = NSRect(x: 20, y: bounds.height-42, width: 26, height: 26)
        heading.frame = NSRect(x: 56, y: bounds.height-40, width: bounds.width-150, height: 22)
        pinControl.frame = NSRect(x: bounds.width-77, y: bounds.height-43, width: 28, height: 28)
        closeControl.frame = NSRect(x: bounds.width-42, y: bounds.height-43, width: 28, height: 28)
        headerLine.frame = NSRect(x: 0, y: bounds.height-57, width: bounds.width, height: 1)
        scroll.frame = NSRect(x: 20, y: 28, width: bounds.width-40, height: bounds.height-102)
        document.frame.size = NSSize(width: scroll.contentSize.width, height: max(scroll.contentSize.height, stack.fittingSize.height+8))
        status.frame = NSRect(x: 20, y: 5, width: bounds.width-40, height: 18)
    }
    func update(state: SystemState, history: WidgetHistory) {
        self.state = state; self.history = history
        if structuralSignature != signature && !busy { rebuild() } else { refreshers.forEach { $0() } }
    }
    private var structuralSignature: String {
        switch kind {
        case .nowPlaying: return state.mediaSessions.map { "\($0.id)|\($0.playback.title)|\($0.playback.artist)|\($0.album)|\($0.canSeek)|\($0.canSkip)|\($0.shuffle != nil)|\($0.repeatMode != nil)" }.joined() + state.providerStatuses.description
        case .audio: return state.audio.devices.map { "\($0.id)|\($0.name)|\($0.isInput)|\($0.canSetVolume)|\($0.canMute)" }.joined() + "\(state.audio.outputID):\(state.audio.inputID)"
        case .calendar: return "\(state.agenda)"
        case .vpn: return "\(state.vpn)"
        case .agentStatus: return state.agents.providers.map { "\($0.id)|\($0.available)|\($0.message)" }.joined()
        default: return "metrics"
        }
    }
    private func rebuild() {
        signature = structuralSignature; refreshers = []; peerContainer = nil
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        switch kind {
        case .nowPlaying: buildMedia()
        case .audio: buildAudio()
        case .calendar: buildCalendar()
        case .vpn: buildVPN()
        case .agentStatus: buildAgents()
        default: buildSystem()
        }
        refreshers.forEach { $0() }; needsLayout = true
    }
    private func text(_ value: String, size: CGFloat = 12, muted: Bool = false, width: CGFloat? = nil, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: value)
        field.font = config.appearance.font(size: size, weight: weight)
        field.textColor = muted ? config.theme.muted : config.theme.foreground
        if let width { field.widthAnchor.constraint(equalToConstant: width).isActive = true }
        return field
    }
    private func add(_ view: NSView, width: CGFloat? = nil, height: CGFloat? = nil, to target: NSStackView? = nil) {
        if let width { view.widthAnchor.constraint(equalToConstant: width).isActive = true }
        if let height { view.heightAnchor.constraint(equalToConstant: height).isActive = true }
        (target ?? stack).addArrangedSubview(view)
    }
    @discardableResult private func label(_ value: String, size: CGFloat = 12, muted: Bool = false) -> NSTextField {
        let field = text(value, size: size, muted: muted, width: bodyWidth); add(field); return field
    }
    private func column(width: CGFloat, spacing: CGFloat = 8) -> NSStackView {
        let column = NSStackView(); column.orientation = .vertical; column.alignment = .leading; column.spacing = spacing
        column.widthAnchor.constraint(equalToConstant: width).isActive = true; return column
    }
    private func row(_ views: [NSView], spacing: CGFloat = 10) -> NSStackView {
        let row = NSStackView(views: views); row.orientation = .horizontal; row.alignment = .centerY; row.spacing = spacing; return row
    }
    private func rule(width: CGFloat? = nil, to target: NSStackView? = nil) {
        let rule = NSBox(); rule.boxType = .separator; add(rule, width: width ?? bodyWidth, height: 1, to: target)
    }
    private func button(_ title: String, treatment: WidgetActionButton.Treatment = .outline, action: @escaping () -> Void) -> WidgetActionButton {
        let button = WidgetActionButton(title, handler: action); button.widgetTheme = config.theme; button.treatment = treatment
        button.font = config.appearance.font(size: 12); button.lineBreakMode = .byTruncatingTail; return button
    }
    private func iconButton(_ symbol: String, label: String, size: CGFloat = 18, action: @escaping () -> Void) -> WidgetActionButton {
        let b = button("", treatment: .plain, action: action); b.symbolName = symbol; b.symbolSize = size
        b.setAccessibilityLabel(label); b.toolTip = label; return b
    }
    private func actionRow(_ title: String, symbol: String, action: @escaping () -> Void) -> WidgetActionButton {
        let b = button(title, treatment: .plain, action: action); b.leading = true; b.symbolName = symbol; b.trailing = "›"; return b
    }
    private func choices(_ titles: [String], selected: Int, width: CGFloat, action: @escaping (Int) -> Void) -> NSStackView {
        let buttons = titles.enumerated().map { index, title -> NSView in
            let b = button(config.appearance == .typeset && index == selected ? "[\(title)]" : title, treatment: .plain) { action(index) }
            b.horizontalPadding = 3
            b.setButtonType(.toggle); b.state = index == selected ? .on : .off
            b.widthAnchor.constraint(equalToConstant: (width-4*CGFloat(titles.count-1))/CGFloat(titles.count)).isActive = true
            b.heightAnchor.constraint(equalToConstant: 30).isActive = true
            return b
        }
        return row(buttons, spacing: 4)
    }
    private func perform(_ action: WidgetAction) {
        guard !busy, let onAction else { return }; busy = true; status.stringValue = "Applying…"
        onAction(action) { [weak self] error in
            guard let self else { return }; self.busy = false
            self.status.stringValue = error ?? ""; self.status.textColor = error == nil ? self.config.theme.muted : self.config.theme.red
            self.status.toolTip = error
        }
    }
    private func openApp(_ id: String) {
        let ids = id == "com.surfshark.vpnclient.macos" ? ["com.surfshark.vpnclient.macos.direct", id] : id == "io.tailscale.ipn.macos" ? ["io.tailscale.ipn.macsys", id] : [id]
        guard let url = ids.compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }).first else { status.stringValue = "This application is not installed."; return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in }
    }
    private func openURL(_ value: String) { if let url = URL(string: value) { NSWorkspace.shared.open(url) } }

    private func buildMedia() {
        let sessions = state.mediaSessions
        if !sessions.contains(where: { $0.id == selectedSession }) { selectedSession = sessions.first(where: { $0.playback.isPlaying })?.id ?? sessions.first?.id ?? "" }
        if sessions.count > 1 {
            let popup = NSPopUpButton(); popup.addItems(withTitles: sessions.map { "\($0.playback.source) · \($0.playback.title.prefix(32))" })
            popup.selectItem(at: sessions.firstIndex(where: { $0.id == selectedSession }) ?? 0)
            popup.target = self; popup.action = #selector(mediaSourceChanged(_:)); add(popup, width: bodyWidth)
        }
        guard let session = sessions.first(where: { $0.id == selectedSession }) else {
            let glyph = PanelGlyph(); glyph.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil); glyph.color = config.theme.muted; glyph.tile = config.theme.surface
            add(row([NSView(), glyph, NSView()]), width: bodyWidth, height: 80); glyph.widthAnchor.constraint(equalToConstant: 80).isActive = true
            label(state.mediaNeedsAttention ? "Music needs attention" : "Nothing playing", size: 23)
            for provider in state.providerStatuses where ["appleMusic", "browser"].contains(provider.id) { label(provider.message, muted: true) }
            if config.providerPreferences.includes("appleMusic") {
                add(button("Open Apple Music") { [weak self] in self?.openApp("com.apple.Music") }, width: bodyWidth, height: 34)
                add(button("Allow Apple Music access") { [weak self] in self?.perform(.authorizeMusic) }, width: bodyWidth, height: 34)
            }
            add(button("Browser setup guide") { [weak self] in self?.openBrowserGuide() }, width: bodyWidth, height: 34)
            return
        }
        let art = NSImageView(); art.image = session.artwork.flatMap(NSImage.init(data:)) ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: "Artwork unavailable")
        art.imageScaling = .scaleProportionallyUpOrDown; art.wantsLayer = true; art.layer?.cornerRadius = 9; art.layer?.masksToBounds = true
        art.widthAnchor.constraint(equalToConstant: 148).isActive = true; art.heightAnchor.constraint(equalToConstant: 148).isActive = true
        let metadata = column(width: bodyWidth-166, spacing: 8)
        add(text("NOW PLAYING", size: 10, muted: true), to: metadata)
        add(text(session.playback.title, size: 21, width: bodyWidth-166, weight: .semibold), to: metadata)
        add(text(session.playback.artist, size: 13, width: bodyWidth-166), to: metadata)
        add(text(session.album.isEmpty ? session.playback.source : session.album, size: 12, muted: true, width: bodyWidth-166), to: metadata)
        add(row([art, metadata], spacing: 18), height: 148)
        let elapsed = text("0:00", size: 11, muted: true, width: 40)
        let duration = text(WidgetCatalog.formatTime(session.playback.duration), size: 11, muted: true, width: 40); duration.alignment = .right
        let slider = WidgetSlider(value: session.playback.position, max: max(1, session.playback.duration), label: "Playback position") { [weak self] seconds in self?.perform(.seek(session: session.id, seconds: seconds)) }
        slider.isEnabled = session.canSeek; slider.widthAnchor.constraint(equalToConstant: bodyWidth-100).isActive = true
        add(row([elapsed, slider, duration]), width: bodyWidth, height: 26)
        let shuffle = iconButton("shuffle", label: "Shuffle") { [weak self] in self?.perform(.playback(session: session.id, command: .toggleShuffle)) }
        shuffle.isEnabled = session.shuffle != nil; shuffle.setButtonType(.toggle)
        let previous = iconButton("backward.end.fill", label: "Previous track", size: 23) { [weak self] in self?.perform(.playback(session: session.id, command: .previous)) }; previous.isEnabled = session.canSkip
        let play = iconButton("pause.fill", label: "Pause", size: 32) { [weak self] in self?.perform(.playback(session: session.id, command: .playPause)) }
        let next = iconButton("forward.end.fill", label: "Next track", size: 23) { [weak self] in self?.perform(.playback(session: session.id, command: .next)) }; next.isEnabled = session.canSkip
        let repeatButton = iconButton("repeat", label: "Repeat") { [weak self] in self?.perform(.playback(session: session.id, command: .cycleRepeat)) }; repeatButton.isEnabled = session.repeatMode != nil; repeatButton.setButtonType(.toggle)
        let transport = row([shuffle, previous, play, next, repeatButton], spacing: 0); transport.distribution = .fillEqually
        add(transport, width: bodyWidth, height: 46)
        refreshers.append { [weak self, weak elapsed, weak slider, weak play, weak shuffle, weak repeatButton] in
            guard let current = self?.state.mediaSessions.first(where: { $0.id == session.id }) else { return }
            elapsed?.stringValue = WidgetCatalog.formatTime(current.playback.position)
            play?.symbolName = current.playback.isPlaying ? "pause.fill" : "play.fill"; play?.setAccessibilityLabel(current.playback.isPlaying ? "Pause" : "Play")
            if slider?.cell?.isHighlighted != true { slider?.doubleValue = current.playback.position }
            shuffle?.state = current.shuffle == true ? .on : .off; shuffle?.setAccessibilityLabel(current.shuffle == true ? "Shuffle on" : "Shuffle off")
            repeatButton?.symbolName = current.repeatMode == .one ? "repeat.1" : "repeat"
            repeatButton?.state = current.repeatMode != nil && current.repeatMode != .off ? .on : .off
            repeatButton?.setAccessibilityLabel("Repeat " + (current.repeatMode?.rawValue ?? "unavailable"))
        }
        rule()
        add(choices(["Playing", "Up next"], selected: mediaTab, width: bodyWidth) { [weak self] index in self?.mediaTab = index; self?.rebuild() })
        if mediaTab == 0 {
            let now = actionRow(session.playback.title, symbol: "music.note") { [weak self] in if session.providerID == "appleMusic" { self?.openApp("com.apple.Music") } }
            now.subtitle = session.playback.source; now.trailing = WidgetCatalog.formatTime(session.playback.duration)
            add(now, width: bodyWidth, height: 44)
        } else {
            label("This provider does not expose its Up Next queue to the bar.", size: 11, muted: true)
            if session.providerID == "appleMusic" { add(button("View queue in Music") { [weak self] in self?.openApp("com.apple.Music") }, width: bodyWidth, height: 30) }
        }
        rule()
        add(actionRow(state.audio.output?.name ?? "Audio output", symbol: state.audio.output?.symbol ?? "headphones") { [weak self] in self?.onOpenAudio?() }, width: bodyWidth, height: 36)
    }
    @objc private func mediaSourceChanged(_ sender: NSPopUpButton) {
        guard state.mediaSessions.indices.contains(sender.indexOfSelectedItem) else { return }
        selectedSession = state.mediaSessions[sender.indexOfSelectedItem].id; rebuild()
    }
    private func openBrowserGuide() {
        if let url = Bundle.main.url(forResource: "BrowserMedia-README", withExtension: "md") { NSWorkspace.shared.open(url) }
        else { status.stringValue = "See extensions/browser-media/README.md in the project." }
    }

    private func buildAgents() {
        let count = label("", size: 48)
        let caption = label("", size: 13)
        rule()
        if state.agents.providers.isEmpty {
            label("Enable an agent provider in Customize Bar → Connections.", muted: true)
        }
        for provider in state.agents.providers {
            label(provider.name, size: 15)
            let summary = label("", size: 12)
            label(provider.message, size: 11, muted: true)
            refreshers.append { [weak self, weak summary] in
                guard let current = self?.state.agents.providers.first(where: { $0.id == provider.id }) else { return }
                summary?.stringValue = current.available ? "\(current.activeCount) active   ·   \(current.idleCount) idle   ·   \(current.unknownCount) unknown" : "Unavailable"
            }
        }
        rule()
        label("Active includes tasks waiting for your input or approval. Counts cover saved tasks on this Mac. Cloud, remote and temporary internal sessions are excluded.", size: 11, muted: true)
        refreshers.append { [weak self, weak count, weak caption] in
            guard let self else { return }
            count?.stringValue = self.state.agents.isComplete ? "\(self.state.agents.activeCount)" : "—"
            count?.textColor = self.state.agents.activeCount > 0 ? self.config.theme.green : self.config.theme.foreground
            caption?.stringValue = self.state.agents.isComplete ? "Active local tasks" : self.state.agents.providers.isEmpty ? "Monitoring disabled" : "Status unavailable or incomplete"
            if let date = self.state.agents.providers.compactMap(\.sampledAt).min() {
                self.status.stringValue = "Checked " + DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .medium)
            }
        }
    }

    private func buildAudio() {
        add(choices(["Output", "Input"], selected: selectedTab, width: bodyWidth) { [weak self] index in self?.selectedTab = index; self?.rebuild() })
        let input = selectedTab == 1, id = selectedTab == 1 ? state.audio.inputID : state.audio.outputID
        let devices = state.audio.devices.filter { $0.isInput == input }
        label(input ? "Input volume" : "Output volume", size: 13)
        if let selected = devices.first(where: { $0.id == id }) {
            let glyph = PanelGlyph(); glyph.image = NSImage(systemSymbolName: input ? "mic" : "speaker.wave.2", accessibilityDescription: nil); glyph.color = config.theme.foreground
            glyph.widthAnchor.constraint(equalToConstant: 24).isActive = true; glyph.heightAnchor.constraint(equalToConstant: 24).isActive = true
            let percent = text("", size: 11, width: 38); percent.alignment = .right
            let slider = WidgetSlider(value: selected.volume ?? 0, max: 1, label: input ? "Input volume" : "Output volume") { [weak self] value in self?.perform(.audioVolume(id, input: input, value: value)) }; slider.isEnabled = selected.canSetVolume
            slider.widthAnchor.constraint(equalToConstant: bodyWidth-136).isActive = true
            let mute = iconButton("speaker.slash", label: "Mute") { [weak self] in
                guard let self else { return }; let muted = self.state.audio.devices.first { $0.id == id && $0.isInput == input }?.muted ?? false
                self.perform(.audioMute(id, input: input, muted: !muted))
            }; mute.treatment = .outline; mute.isEnabled = selected.canMute; mute.setButtonType(.toggle)
            mute.widthAnchor.constraint(equalToConstant: 44).isActive = true; mute.heightAnchor.constraint(equalToConstant: 36).isActive = true
            add(row([glyph, slider, percent, mute]), width: bodyWidth, height: 42)
            refreshers.append { [weak self, weak slider, weak percent, weak mute] in
                guard let device = self?.state.audio.devices.first(where: { $0.id == id && $0.isInput == input }) else { return }
                percent?.stringValue = device.volume.map { "\(Int($0*100))%" } ?? "—"
                if slider?.cell?.isHighlighted != true { slider?.doubleValue = device.volume ?? 0 }
                mute?.state = device.muted == true ? .on : .off; mute?.setAccessibilityLabel(device.muted == true ? "Unmute" : "Mute")
            }
            if !selected.canSetVolume { label("Use this device’s hardware volume controls.", size: 11, muted: true) }
        }
        rule(); label(input ? "Select input device" : "Select output device", size: 13)
        let card = PanelCard(width: bodyWidth, theme: config.theme)
        for (index, device) in devices.enumerated() {
            if index > 0 { rule(width: bodyWidth-24, to: card.content) }
            let b = button(device.name, treatment: device.id == id ? .outline : .plain) { [weak self] in self?.perform(.audioDevice(device.id, input: input)) }
            b.leading = true; b.symbolName = device.symbol; b.subtitle = device.transport == kAudioDeviceTransportTypeBluetooth || device.transport == kAudioDeviceTransportTypeBluetoothLE ? "Bluetooth" : device.transport == kAudioDeviceTransportTypeBuiltIn ? "Built-in" : "Audio device"
            b.trailing = device.id == id ? "✓" : ""; b.statusColor = config.theme.blue
            b.setAccessibilityValue(b.subtitle + (device.id == id ? ", selected" : ""))
            add(b, width: bodyWidth-24, height: 58, to: card.content)
        }
        if devices.isEmpty { add(text("No devices available", muted: true), to: card.content) }
        add(card); rule()
        add(actionRow("Sound settings…", symbol: "slider.horizontal.3") { [weak self] in self?.openURL("x-apple.systempreferences:com.apple.Sound-Settings.extension") }, width: bodyWidth, height: 34)
    }

    private func buildVPN() {
        let active = state.vpn.connections.filter(\.connected).count
        label("\(active) active connection\(active == 1 ? "" : "s")", size: 13, muted: true)
        if selectedVPN.isEmpty { selectedVPN = state.vpn.connections.first(where: { !$0.peers.isEmpty })?.id ?? state.vpn.connections.first(where: \.connected)?.id ?? "" }
        if state.vpn.connections.isEmpty { label("No VPN services found. Check provider setup in Connections.", muted: true) }
        for connection in state.vpn.connections {
            let expanded = connection.id == selectedVPN
            let card = PanelCard(width: bodyWidth, theme: config.theme, selected: expanded && connection.connected)
            let inner = bodyWidth-24
            let tile = PanelGlyph()
            tile.image = NSImage(systemSymbolName: connection.symbol, accessibilityDescription: connection.serviceName)
            tile.color = config.theme.foreground; tile.tile = config.theme.surfaceStrong
            let appIDs = connection.provider == "surfshark" ? ["com.surfshark.vpnclient.macos.direct", "com.surfshark.vpnclient.macos"] : connection.provider == "tailscale" ? ["io.tailscale.ipn.macsys", "io.tailscale.ipn.macos"] : []
            if let appURL = appIDs.compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }).first {
                tile.image = NSWorkspace.shared.icon(forFile: appURL.path)
                tile.preservesImageColors = true; tile.tile = nil
            }
            tile.setAccessibilityLabel(connection.serviceName)
            tile.widthAnchor.constraint(equalToConstant: 34).isActive = true; tile.heightAnchor.constraint(equalToConstant: 34).isActive = true
            let title = column(width: inner-172, spacing: 4)
            add(text(connection.serviceName, size: 13, width: inner-172, weight: .semibold), to: title)
            var subtitle = connection.provider == "tailscale" ? "Mesh network" : connection.protocolName.isEmpty ? "VPN service" : connection.protocolName
            if state.vpn.connections.filter({ $0.serviceName == connection.serviceName }).count > 1 && !connection.id.isEmpty { subtitle += " · " + connection.id.prefix(6) }
            add(text(subtitle, size: 11, muted: true), to: title)
            let badge = text(connection.connected ? "● Connected" : "● Offline", size: 11, width: 92)
            badge.textColor = connection.connected ? (config.appearance == .cove ? config.theme.blue : config.theme.green) : config.theme.muted
            let expand = iconButton(expanded ? "chevron.up" : "chevron.down", label: expanded ? "Collapse \(connection.serviceName)" : "Expand \(connection.serviceName)", size: 12) { [weak self] in self?.selectedVPN = expanded ? "collapsed" : connection.id; self?.peerQuery = ""; self?.rebuild() }
            expand.widthAnchor.constraint(equalToConstant: 22).isActive = true; expand.heightAnchor.constraint(equalToConstant: 30).isActive = true
            add(row([tile, title, badge, expand], spacing: 8), width: inner, height: 44, to: card.content)
            if expanded {
                rule(width: inner, to: card.content)
                if !connection.profileName.isEmpty { add(text("Profile · " + connection.profileName, size: 12, width: inner), to: card.content) }
                add(text(connection.detail, size: 11, muted: true, width: inner), to: card.content)
                if !connection.peers.isEmpty {
                    add(text("Devices", size: 13, weight: .semibold), to: card.content)
                    let search = NSSearchField(); search.placeholderString = "Find a device"; search.stringValue = peerQuery
                    search.setAccessibilityLabel("Find a VPN device"); search.delegate = self
                    add(search, width: inner, height: 28, to: card.content)
                    let peers = column(width: inner); peerContainer = peers; currentPeers = connection.peers; add(peers, to: card.content); updatePeers()
                }
                let action: WidgetActionButton
                if connection.canToggle { action = button(connection.connected ? "Disconnect" : "Connect") { [weak self] in self?.perform(.vpn(service: connection.id, connected: !connection.connected)) } }
                else { action = button(connection.provider == "tailscale" ? "Open Tailscale" : connection.provider == "surfshark" ? "Open Surfshark" : "VPN settings") { [weak self] in
                    if connection.provider == "tailscale" { self?.openApp("io.tailscale.ipn.macos") }
                    else if connection.provider == "surfshark" { self?.openApp("com.surfshark.vpnclient.macos") }
                    else { self?.openURL("x-apple.systempreferences:com.apple.NetworkExtensionSettingsUI.NESettingsUIExtension") }
                } }
                add(action, width: inner, height: 32, to: card.content)
            }
            add(card)
        }
        label("Routing details depend on the provider.", size: 11, muted: true)
    }
    func controlTextDidChange(_ notification: Notification) {
        guard let search = notification.object as? NSSearchField else { return }; peerQuery = search.stringValue; updatePeers()
    }
    private func updatePeers() {
        guard let container = peerContainer else { return }
        container.arrangedSubviews.forEach { container.removeArrangedSubview($0); $0.removeFromSuperview() }
        let matches = currentPeers.filter { peerQuery.isEmpty || $0.localizedCaseInsensitiveContains(peerQuery) }
        for peer in matches {
            let pieces = peer.components(separatedBy: " · ")
            let glyph = PanelGlyph(); glyph.image = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: nil); glyph.color = config.theme.muted
            glyph.widthAnchor.constraint(equalToConstant: 20).isActive = true; glyph.heightAnchor.constraint(equalToConstant: 20).isActive = true
            let name = text(pieces.first ?? peer, size: 12, width: bodyWidth-144)
            let online = pieces.last == "Online"; let status = text(online ? "● Online" : "● Offline", size: 11, width: 70); status.textColor = online ? (config.appearance == .cove ? config.theme.blue : config.theme.green) : config.theme.muted
            add(row([glyph, name, status], spacing: 8), height: 30, to: container)
        }
        if matches.isEmpty { add(text("No matching devices", size: 11, muted: true), to: container) }
        needsLayout = true
    }

    private func changeDay(_ candidate: Date) {
        guard candidate >= (state.agenda.rangeStart ?? candidate), candidate < (state.agenda.rangeEnd ?? candidate.addingTimeInterval(1)) else { status.stringValue = "Agenda covers the past week and next three weeks."; return }
        day = candidate; selectedEvent = nil; rebuild()
    }
    private func buildCalendar() {
        guard state.agenda.authorized else {
            label("Your day, at a glance", size: 28); label(state.agenda.message, muted: true)
            if config.providerPreferences.includes("appleCalendar") { add(button("Allow Calendar access") { [weak self] in self?.perform(.authorizeCalendar) }, width: bodyWidth, height: 34) }
            label("Includes calendars already synced to this Mac.", size: 11, muted: true); return
        }
        if calendarChooser {
            label("Choose calendars", size: 24)
            for source in state.agenda.calendars {
                let toggle = button(source.title, treatment: .plain) { [weak self] in
                    guard let self else { return }
                    if self.hiddenCalendars.contains(source.id) { self.hiddenCalendars.remove(source.id) } else { self.hiddenCalendars.insert(source.id) }
                    UserDefaults.standard.set(Array(self.hiddenCalendars), forKey: "hiddenWidgetCalendars"); self.rebuild()
                }
                toggle.leading = true; toggle.symbolName = hiddenCalendars.contains(source.id) ? "square" : "checkmark.square.fill"; toggle.subtitle = source.account
                toggle.setAccessibilityValue(hiddenCalendars.contains(source.id) ? "Hidden" : "Shown"); add(toggle, width: bodyWidth, height: 48)
            }
            add(button("Done") { [weak self] in self?.calendarChooser = false; self?.rebuild() }, width: bodyWidth, height: 34); return
        }
        let formatter = DateFormatter(); formatter.dateFormat = "EEEE, d"
        let headline = text(formatter.string(from: day), size: 30, width: bodyWidth-100)
        if config.appearance == .porcelain { headline.font = NSFont(name: "Georgia", size: 30) }
        let prev = iconButton("chevron.left", label: "Previous day", size: 13) { [weak self] in guard let self else { return }; self.changeDay(Calendar.current.date(byAdding: .day, value: -1, to: self.day)!) }
        let next = iconButton("chevron.right", label: "Next day", size: 13) { [weak self] in guard let self else { return }; self.changeDay(Calendar.current.date(byAdding: .day, value: 1, to: self.day)!) }
        for b in [prev, next] { b.widthAnchor.constraint(equalToConstant: 30).isActive = true; b.heightAnchor.constraint(equalToConstant: 30).isActive = true }
        add(row([headline, prev, next]), width: bodyWidth)
        formatter.dateFormat = "MMMM"; label(formatter.string(from: day), size: 13, muted: true)
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: day)!.start
        let week = row([], spacing: 5)
        for offset in 0..<7 {
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            formatter.dateFormat = "EEE"
            let cell = column(width: (bodyWidth-30)/7, spacing: 4)
            let weekday = text(formatter.string(from: date).uppercased(), size: 9, muted: true, width: (bodyWidth-30)/7); weekday.alignment = .center; add(weekday, to: cell)
            let b = button(String(calendar.component(.day, from: date)), treatment: .plain) { [weak self] in self?.changeDay(date) }
            b.circularSelection = true
            b.setButtonType(.toggle); b.state = calendar.isDate(date, inSameDayAs: day) ? .on : .off
            b.setAccessibilityLabel(DateFormatter.localizedString(from: date, dateStyle: .full, timeStyle: .none))
            add(b, width: (bodyWidth-30)/7, height: 30, to: cell); week.addArrangedSubview(cell)
        }
        add(week); rule()
        let end = calendar.date(byAdding: .day, value: 1, to: day)!
        let events = state.agenda.events.filter { $0.start < end && $0.end > day && !hiddenCalendars.contains($0.calendarID) }
        if selectedEvent == nil { selectedEvent = events.first?.id }
        let half = (bodyWidth-24)/2
        let agenda = column(width: half, spacing: 8), details = column(width: half, spacing: 10)
        for event in events {
            let time = event.allDay ? "All day" : DateFormatter.localizedString(from: event.start, dateStyle: .none, timeStyle: .short)
            let b = button(event.title, treatment: .plain) { [weak self] in self?.selectedEvent = event.id; self?.rebuild() }
            b.subtleSelection = true; b.leading = true; b.subtitle = time + " · " + event.calendar; b.setButtonType(.toggle); b.state = selectedEvent == event.id ? .on : .off
            b.setAccessibilityValue(b.subtitle); add(b, width: half, height: 62, to: agenda)
        }
        if events.isEmpty { add(text("Nothing scheduled", size: 17, muted: true, width: half), to: agenda) }
        if let event = events.first(where: { $0.id == selectedEvent }) {
            add(text(event.title, size: 17, width: half, weight: .semibold), to: details)
            add(text(event.calendar, size: 12, muted: true, width: half), to: details)
            add(text(DateFormatter.localizedString(from: event.start, dateStyle: .none, timeStyle: .short) + " – " + DateFormatter.localizedString(from: event.end, dateStyle: .none, timeStyle: .short), size: 12, width: half), to: details)
            if !event.location.isEmpty { add(text(event.location, size: 12, muted: true, width: half), to: details) }
            if !event.attendees.isEmpty { add(text(event.attendees.prefix(5).joined(separator: ", "), size: 11, muted: true, width: half), to: details) }
            if let url = event.meetingURL { let join = button("Join meeting", treatment: .filled) { NSWorkspace.shared.open(url) }; join.symbolName = "video.fill"; add(join, width: half, height: 34, to: details) }
            add(button("Open in Calendar") { [weak self] in self?.openApp("com.apple.iCal") }, width: half, height: 32, to: details)
        }
        let columns = row([agenda, details], spacing: 24); columns.alignment = .top; add(columns, width: bodyWidth)
        rule()
        let zone = text("All times in your local time zone", size: 10, muted: true, width: bodyWidth-44)
        let choose = iconButton("gearshape", label: "Choose calendars", size: 17) { [weak self] in self?.calendarChooser = true; self?.rebuild() }
        choose.widthAnchor.constraint(equalToConstant: 30).isActive = true; choose.heightAnchor.constraint(equalToConstant: 28).isActive = true
        add(row([zone, choose]), width: bodyWidth)
    }

    private func buildSystem() {
        add(choices(["CPU", "MEMORY", "NETWORK"], selected: selectedTab, width: bodyWidth) { [weak self] index in self?.selectedTab = index; self?.rebuild() }); rule()
        let metric = text("", size: 38, width: bodyWidth-160); metric.textColor = config.theme.blue
        let ranges = choices(["1m", "5m", "1h"], selected: rangeSeconds == 60 ? 0 : rangeSeconds == 300 ? 1 : 2, width: 150) { [weak self] index in self?.rangeSeconds = [60,300,3600][index]; self?.rebuild() }
        add(row([metric, ranges]), width: bodyWidth)
        let detail = label("", size: 12, muted: true)
        let graph = MetricPlot(); graph.theme = config.theme; graph.seconds = rangeSeconds; graph.percentage = selectedTab != 2
        graph.setAccessibilityLabel("Metric history"); add(graph, width: bodyWidth, height: 122); rule()
        let tableHead = text(selectedTab == 1 ? "MEMORY BREAKDOWN" : selectedTab == 2 ? "TRANSFER RATE" : "TOP PROCESSES", size: 11, muted: true, width: bodyWidth-70)
        let sort = button(selectedTab == 1 ? "Bytes" : "CPU ↓", treatment: .plain) { [weak self] in self?.processAscending.toggle(); self?.rebuild() }
        sort.widthAnchor.constraint(equalToConstant: 60).isActive = true; sort.heightAnchor.constraint(equalToConstant: 22).isActive = true
        sort.isEnabled = selectedTab == 0
        add(row([tableHead, sort]), width: bodyWidth)
        var cells: [(NSTextField, NSTextField)] = []
        for _ in 0..<3 {
            let name = text("", size: 12, width: bodyWidth-100), value = text("", size: 12, width: 90); value.alignment = .right
            add(row([name, value]), width: bodyWidth, height: 22); cells.append((name,value)); rule()
        }
        let thermal = text("", size: 10, muted: true, width: bodyWidth-170)
        let open = button("Open Activity Monitor", treatment: .plain) { [weak self] in self?.openApp("com.apple.ActivityMonitor") }; open.horizontalPadding = 2; open.font = config.appearance.font(size: 11); open.widthAnchor.constraint(equalToConstant: 160).isActive = true; open.heightAnchor.constraint(equalToConstant: 26).isActive = true
        add(row([thermal, open]), width: bodyWidth)
        refreshers.append { [weak self, weak metric, weak detail, weak graph, weak thermal] in
            guard let self else { return }
            let h = self.history, start = Date(timeIntervalSinceNow: -self.rangeSeconds)
            let count = h.dates.filter { $0 >= start }.count
            if self.selectedTab == 0 {
                metric?.stringValue = "\(Int(self.state.cpu.usage))%"; detail?.stringValue = "CPU usage"
                graph?.values = Array(h.cpu.suffix(count))
                let processes = self.state.topProcesses.sorted { self.processAscending ? $0.cpu < $1.cpu : $0.cpu > $1.cpu }
                for (index, cell) in cells.enumerated() { cell.0.stringValue = processes.indices.contains(index) ? processes[index].name : "—"; cell.1.stringValue = processes.indices.contains(index) ? String(format:"%.1f%%", processes[index].cpu) : "" }
            } else if self.selectedTab == 1 {
                metric?.stringValue = ByteFormatter.bytes(self.state.memory.usedBytes); detail?.stringValue = "of \(ByteFormatter.bytes(self.state.memory.totalBytes)) memory"
                graph?.values = Array(h.memory.suffix(count))
                let breakdown = [("Active", self.state.memory.activeBytes), ("Wired", self.state.memory.wiredBytes), ("Compressed", self.state.memory.compressedBytes)]
                for (index, cell) in cells.enumerated() { cell.0.stringValue = breakdown[index].0; cell.1.stringValue = ByteFormatter.bytes(breakdown[index].1) }
            } else {
                metric?.stringValue = ByteFormatter.compactSpeed(self.state.network.downloadBytesPerSecond); detail?.stringValue = "Download · history scales to peak"
                graph?.values = Array(h.network.suffix(count))
                let values = [("Download", ByteFormatter.speed(self.state.network.downloadBytesPerSecond)), ("Upload", ByteFormatter.speed(self.state.network.uploadBytesPerSecond)), ("History", "\(count) samples")]
                for (index, cell) in cells.enumerated() { cell.0.stringValue = values[index].0; cell.1.stringValue = values[index].1 }
            }
            graph?.dates = Array(h.dates.suffix(count)); thermal?.stringValue = "Thermal state · \(self.state.thermal.label)"
        }
    }
    private var processAscending = false
}
