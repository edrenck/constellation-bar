import AppKit
import CoreAudio

final class WidgetSlider: NSSlider {
    var handler: ((Double) -> Void)?
    convenience init(value: Double, max: Double, label: String, handler: @escaping (Double) -> Void) {
        self.init(value: value, minValue: 0, maxValue: max, target: nil, action: nil)
        self.handler = handler; target = self; action = #selector(changed)
        isContinuous = false; setAccessibilityLabel(label)
    }
    @objc func changed() { handler?(doubleValue) }
}
final class PanelDocument: NSView { override var isFlipped: Bool { true } }

/// Layouts follow the approved mini-app boards, while adapters own data and capabilities.
final class MiniAppPanel: OverlayContentView, NSSearchFieldDelegate {
    static let kinds: Set<WidgetKind> = [.nowPlaying, .calendar, .vpn, .audio, .system, .cpu, .memory, .agentStatus]
    let kind: WidgetKind
    let config: BarConfig
    var state: SystemState
    var history: WidgetHistory
    let scroll = NSScrollView()
    let document = PanelDocument()
    let stack = NSStackView()
    let heading = NSTextField(labelWithString: "")
    let headerIcon = PanelGlyph()
    let headerLine = NSBox()
    let status = NSTextField(wrappingLabelWithString: "")
    var closeControl: WidgetActionButton!
    var pinControl: WidgetActionButton!
    var pinned = true
    var refreshers: [() -> Void] = []
    var signature = ""
    var selectedSession = ""
    var selectedTab = 0
    var mediaTab = 0
    var rangeSeconds: Double = 300
    var day = Calendar.current.startOfDay(for: Date())
    var calendarChooser = false
    var selectedVPN = ""
    var peerQuery = ""
    var peerContainer: NSStackView?
    var currentPeers: [String] = []
    var selectedEvent: String?
    var hiddenCalendars = Set(UserDefaults.standard.stringArray(forKey: "hiddenWidgetCalendars") ?? [])
    var busy = false
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
    var bodyWidth: CGFloat { preferredSize.width - 40 }
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
    var structuralSignature: String {
        switch kind {
        case .nowPlaying: return state.mediaSessions.map { "\($0.id)|\($0.playback.title)|\($0.playback.artist)|\($0.album)|\($0.canSeek)|\($0.canSkip)|\($0.shuffle != nil)|\($0.repeatMode != nil)" }.joined() + state.providerStatuses.description
        case .audio: return state.audio.devices.map { "\($0.id)|\($0.name)|\($0.isInput)|\($0.canSetVolume)|\($0.canMute)" }.joined() + "\(state.audio.outputID):\(state.audio.inputID)"
        case .calendar: return "\(state.agenda)"
        case .vpn: return "\(state.vpn)"
        case .agentStatus: return state.agents.providers.map { "\($0.id)|\($0.available)|\($0.message)" }.joined()
        default: return "metrics"
        }
    }
    func rebuild() {
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
    func text(_ value: String, size: CGFloat = 12, muted: Bool = false, width: CGFloat? = nil, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: value)
        field.font = config.appearance.font(size: size, weight: weight)
        field.textColor = muted ? config.theme.muted : config.theme.foreground
        if let width { field.widthAnchor.constraint(equalToConstant: width).isActive = true }
        return field
    }
    func add(_ view: NSView, width: CGFloat? = nil, height: CGFloat? = nil, to target: NSStackView? = nil) {
        if let width { view.widthAnchor.constraint(equalToConstant: width).isActive = true }
        if let height { view.heightAnchor.constraint(equalToConstant: height).isActive = true }
        (target ?? stack).addArrangedSubview(view)
    }
    @discardableResult func label(_ value: String, size: CGFloat = 12, muted: Bool = false) -> NSTextField {
        let field = text(value, size: size, muted: muted, width: bodyWidth); add(field); return field
    }
    func column(width: CGFloat, spacing: CGFloat = 8) -> NSStackView {
        let column = NSStackView(); column.orientation = .vertical; column.alignment = .leading; column.spacing = spacing
        column.widthAnchor.constraint(equalToConstant: width).isActive = true; return column
    }
    func row(_ views: [NSView], spacing: CGFloat = 10) -> NSStackView {
        let row = NSStackView(views: views); row.orientation = .horizontal; row.alignment = .centerY; row.spacing = spacing; return row
    }
    func rule(width: CGFloat? = nil, to target: NSStackView? = nil) {
        let rule = NSBox(); rule.boxType = .separator; add(rule, width: width ?? bodyWidth, height: 1, to: target)
    }
    func button(_ title: String, treatment: WidgetActionButton.Treatment = .outline, action: @escaping () -> Void) -> WidgetActionButton {
        let button = WidgetActionButton(title, handler: action); button.widgetTheme = config.theme; button.treatment = treatment
        button.font = config.appearance.font(size: 12); button.lineBreakMode = .byTruncatingTail; return button
    }
    func iconButton(_ symbol: String, label: String, size: CGFloat = 18, action: @escaping () -> Void) -> WidgetActionButton {
        let b = button("", treatment: .plain, action: action); b.symbolName = symbol; b.symbolSize = size
        b.setAccessibilityLabel(label); b.toolTip = label; return b
    }
    func actionRow(_ title: String, symbol: String, action: @escaping () -> Void) -> WidgetActionButton {
        let b = button(title, treatment: .plain, action: action); b.leading = true; b.symbolName = symbol; b.trailing = "›"; return b
    }
    func choices(_ titles: [String], selected: Int, width: CGFloat, action: @escaping (Int) -> Void) -> NSStackView {
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
    func perform(_ action: WidgetAction) {
        guard !busy, let onAction else { return }; busy = true; status.stringValue = "Applying…"
        onAction(action) { [weak self] error in
            guard let self else { return }; self.busy = false
            self.status.stringValue = error ?? ""; self.status.textColor = error == nil ? self.config.theme.muted : self.config.theme.red
            self.status.toolTip = error
        }
    }
    func openApp(_ id: String) {
        let ids = id == "com.surfshark.vpnclient.macos" ? ["com.surfshark.vpnclient.macos.direct", id] : id == "io.tailscale.ipn.macos" ? ["io.tailscale.ipn.macsys", id] : [id]
        guard let url = ids.compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }).first else { status.stringValue = "This application is not installed."; return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in }
    }
    func openURL(_ value: String) { if let url = URL(string: value) { NSWorkspace.shared.open(url) } }

    var processAscending = false
}
