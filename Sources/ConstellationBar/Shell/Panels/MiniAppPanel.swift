import AppKit
import CoreAudio

final class WidgetSlider: NSSlider {
    var handler: ((Double) -> Void)?
    convenience init(value: Double, max: Double, label: String, handler: @escaping (Double) -> Void) {
        self.init(value: value, minValue: 0, maxValue: max, target: nil, action: nil)
        self.handler = handler; target = self; action = #selector(changed)
        isContinuous = false; setAccessibilityLabel(label); identifier = NSUserInterfaceItemIdentifier("slider.\(label)")
    }
    @objc func changed() { handler?(doubleValue) }
}
final class PanelDocument: NSView { override var isFlipped: Bool { true } }

/// Layouts follow the approved mini-app boards, while adapters own data and capabilities.
final class MiniAppPanel: OverlayContentView, NSSearchFieldDelegate {
    static let kinds: Set<WidgetKind> = [.timer, .keepAwake, .reminders, .keyboard, .dateTime, .nowPlaying, .calendar, .vpn, .audio, .system, .cpu, .memory, .agentStatus, .battery, .weather]
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
    let overflowHint = NSTextField(labelWithString: "Scroll for more")
    private(set) var actionError: String?
    private(set) var feedbackDetails: WidgetActionButton!
    private var bodyWidthConstraint: NSLayoutConstraint?
    var closeControl: WidgetActionButton!
    var pinControl: WidgetActionButton!
    var pinned = true
    var refreshers: [() -> Void] = []
    var signature = ""
    private lazy var calendarContent = CalendarPanelContent(panel: self)
    private lazy var mediaContent = MediaPanelContent(panel: self)
    private lazy var keepAwakeContent = KeepAwakePanelContent(panel: self)
    private lazy var systemContent = SystemPanelContent(panel: self)
    private lazy var timerContent = TimerPanelContent(panel: self)
    private(set) var compactContent = false
    var selectedTab = 0
    var selectedVPN = ""
    var peerQuery = ""
    var peerContainer: NSStackView?
    var currentPeers: [String] = []
    var busy = false
    var onAction: ((WidgetAction, @escaping (String?) -> Void) -> Void)?
    var onClose: (() -> Void)?
    var onOpenAudio: (() -> Void)?
    var onPinChange: ((Bool) -> Void)?
    var preferredSize: NSSize {
        switch kind {
        case .timer, .keepAwake, .keyboard, .dateTime: return NSSize(width: 420, height: 430)
        case .reminders: return NSSize(width: 460, height: 520)
        case .agentStatus: return NSSize(width: 440, height: 480)
        case .calendar: return NSSize(width: 620, height: 530)
        case .nowPlaying: return NSSize(width: 440, height: 550)
        case .vpn: return NSSize(width: 480, height: 540)
        case .audio: return NSSize(width: 420, height: 490)
        default: return NSSize(width: 460, height: 540)
        }
    }
    var bodyWidth: CGFloat {
        max(240, min(preferredSize.width-40, bounds.width > 40 ? bounds.width-40 : preferredSize.width-40))
    }
    init(kind: WidgetKind, state: SystemState, config: BarConfig, history: WidgetHistory) {
        self.kind = kind; self.state = state; self.config = config; self.history = history
        super.init(frame: .zero)
        applyAppearance(theme: config.theme)
        heading.stringValue = kind == .agentStatus ? "Agent Status*" : kind == .nowPlaying ? "Music" : kind == .vpn ? "VPN & tunnels" : [.cpu, .memory, .system].contains(kind) ? "System" : kind.menuTitle
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
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true; scroll.scrollerStyle = .overlay
        scroll.documentView = document; addSubview(scroll)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = [.system, .cpu, .memory].contains(kind) ? 8 : 14
        stack.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(stack)
        bodyWidthConstraint = stack.widthAnchor.constraint(equalToConstant: bodyWidth)
        NSLayoutConstraint.activateOwned([stack.leadingAnchor.constraint(equalTo: document.leadingAnchor), stack.topAnchor.constraint(equalTo: document.topAnchor), bodyWidthConstraint!], owner: "panel.\(kind.rawValue).body")
        status.font = config.appearance.font(size: 11); status.textColor = config.theme.muted; addSubview(status)
        status.lineBreakMode = .byTruncatingTail
        status.maximumNumberOfLines = 1
        feedbackDetails = button("Details…", treatment: .plain) { [weak self] in self?.showActionDetails() }
        feedbackDetails.identifier = NSUserInterfaceItemIdentifier("feedback.details")
        feedbackDetails.setAccessibilityLabel("Action error details")
        feedbackDetails.isHidden = true; addSubview(feedbackDetails)
        overflowHint.font = config.appearance.font(size: 10); overflowHint.textColor = config.theme.muted
        overflowHint.alignment = .right; overflowHint.setAccessibilityElement(false); addSubview(overflowHint)
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
        guard bounds.width > 40, bounds.height > 102 else { return }
        let compact = bounds.height-102 < 300
        if let bodyWidthConstraint, abs(bodyWidthConstraint.constant-bodyWidth) > 0.5 || compactContent != compact {
            bodyWidthConstraint.constant = bodyWidth
            compactContent = compact
            stack.spacing = compact || [.system, .cpu, .memory].contains(kind) ? 8 : 14
            rebuild()
        }
        headerIcon.frame = NSRect(x: 20, y: bounds.height-42, width: 26, height: 26)
        heading.frame = NSRect(x: 56, y: bounds.height-40, width: bounds.width-150, height: 22)
        pinControl.frame = NSRect(x: bounds.width-77, y: bounds.height-43, width: 28, height: 28)
        closeControl.frame = NSRect(x: bounds.width-42, y: bounds.height-43, width: 28, height: 28)
        headerLine.frame = NSRect(x: 0, y: bounds.height-57, width: bounds.width, height: 1)
        scroll.frame = NSRect(x: 20, y: 28, width: bounds.width-40, height: bounds.height-102)
        scroll.tile()
        stack.layoutSubtreeIfNeeded()
        document.frame.size = NSSize(width: max(bodyWidth, scroll.contentSize.width), height: max(scroll.contentSize.height, stack.fittingSize.height+8))
        let overflowing = document.frame.height > scroll.contentSize.height+1 || document.frame.width > scroll.contentSize.width+1
        overflowHint.isHidden = !overflowing || actionError != nil
        overflowHint.frame = NSRect(x: max(20, bounds.width-135), y: 5, width: 115, height: 18)
        let detailsWidth = max(72, ceil(feedbackDetails.intrinsicContentSize.width))
        feedbackDetails.frame = NSRect(x: bounds.width-20-detailsWidth, y: 3, width: detailsWidth, height: 22)
        status.frame = NSRect(x: 20, y: 5, width: max(0, bounds.width-40-(actionError != nil ? detailsWidth+8 : overflowing ? 125 : 0)), height: 18)
    }
    func update(state: SystemState, history: WidgetHistory) {
        self.state = state; self.history = history
        if structuralSignature != signature && !busy { rebuild() } else { refreshers.forEach { $0() } }
    }
    var structuralSignature: String {
        switch kind {
        case .nowPlaying: return mediaContent.signature(for: state)
        case .audio: return state.audio.devices.map { "\($0.id)|\($0.name)|\($0.isInput)|\($0.canSetVolume)|\($0.canMute)|\($0.issues)" }.joined() + "\(state.audio.outputID):\(state.audio.inputID):\(state.audio.status):\(state.audio.outputFailure ?? ""):\(state.audio.inputFailure ?? ""):\(state.audio.issues)"
        case .battery: return "\(state.battery)"
        case .weather: return "\(state.weather)"
        case .timer: return "\(state.timer.phase):\(state.timer.duration)"
        case .keepAwake: return "\(state.keepAwake.active):\(state.keepAwake.displayAwake)"
        case .reminders: return "\(state.reminders):\(state.reminders.overdue(at: state.date)):\(TimeZone.current.identifier):\(Locale.current.identifier)"
        case .keyboard: return "\(state.keyboard)"
        case .dateTime: return "worldClock"
        case .calendar: return "\(state.agenda)"
        case .vpn: return "\(state.vpn)"
        case .agentStatus: return state.agents.providers.map { "\($0.id)|\($0.name)|\($0.hostName)|\($0.available)|\($0.message)|\($0.tasks)" }.joined()
        default: return "metrics"
        }
    }
    func rebuild() {
        let focus = PanelFocus(body: stack, window: window)
        signature = structuralSignature; refreshers = []; peerContainer = nil
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        switch kind {
        case .timer: timerContent.build()
        case .keepAwake: keepAwakeContent.build()
        case .reminders: buildReminders()
        case .keyboard: buildKeyboard()
        case .dateTime: buildClock()
        case .nowPlaying: mediaContent.build()
        case .audio: buildAudio()
        case .calendar: calendarContent.build()
        case .vpn: buildVPN()
        case .agentStatus: buildAgents()
        case .battery, .weather: buildStatusDetails()
        default: systemContent.build()
        }
        refreshers.forEach { $0() }; needsLayout = true
        focus?.restore(body: stack, window: window, fallback: closeControl)
    }
    func text(_ value: String, size: CGFloat = 12, muted: Bool = false, width: CGFloat? = nil, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: value)
        field.font = config.appearance.font(size: size, weight: weight)
        field.textColor = muted ? config.theme.muted : config.theme.foreground
        if let width { field.widthAnchor.constraint(equalToConstant: width).isActive = true }
        return field
    }
    func add(_ view: NSView, width: CGFloat? = nil, height: CGFloat? = nil, to target: NSStackView? = nil) {
        if let width { view.widthAnchor.constraint(equalToConstant: width).identified("panel.\(kind.rawValue).item.width").isActive = true }
        if let height { view.heightAnchor.constraint(equalToConstant: height).identified("panel.\(kind.rawValue).item.height").isActive = true }
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
    func buttonRows(_ buttons: [WidgetActionButton]) -> NSStackView {
        let group = column(width: bodyWidth)
        var line: [NSView] = []
        var used: CGFloat = 0
        for button in buttons {
            let width = button.intrinsicContentSize.width
            if !line.isEmpty && used + 10 + width > bodyWidth {
                group.addArrangedSubview(row(line)); line = []; used = 0
            }
            used += (line.isEmpty ? 0 : 10) + width
            line.append(button)
        }
        if !line.isEmpty { group.addArrangedSubview(row(line)) }
        return group
    }
    func rule(width: CGFloat? = nil, to target: NSStackView? = nil) {
        let rule = NSBox(); rule.boxType = .separator; add(rule, width: width ?? bodyWidth, height: 1, to: target)
    }
    func button(_ title: String, treatment: WidgetActionButton.Treatment = .outline, action: @escaping () -> Void) -> WidgetActionButton {
        let button = WidgetActionButton(title, handler: action); button.widgetTheme = config.theme; button.treatment = treatment
        button.identifier = NSUserInterfaceItemIdentifier("button.\(title)")
        button.font = config.appearance.font(size: 12); button.lineBreakMode = .byTruncatingTail; return button
    }
    func iconButton(_ symbol: String, label: String, size: CGFloat = 18, action: @escaping () -> Void) -> WidgetActionButton {
        let b = button("", treatment: .plain, action: action); b.symbolName = symbol; b.symbolSize = size
        b.identifier = NSUserInterfaceItemIdentifier("icon.\(label)")
        b.setAccessibilityLabel(label); b.toolTip = label; return b
    }
    func actionRow(_ title: String, symbol: String, action: @escaping () -> Void) -> WidgetActionButton {
        let b = button(title, treatment: .plain, action: action); b.leading = true; b.symbolName = symbol; b.trailing = "›"; return b
    }
    func choices(_ titles: [String], selected: Int, width: CGFloat, action: @escaping (Int) -> Void) -> NSStackView {
        let buttons = titles.enumerated().map { index, title -> NSView in
            let b = button(config.appearance == .typeset && index == selected ? "[\(title)]" : title, treatment: .plain) { action(index) }
            b.identifier = NSUserInterfaceItemIdentifier("choice.\(titles.joined(separator: "|")).\(index)")
            b.horizontalPadding = 3
            b.setButtonType(.toggle); b.state = index == selected ? .on : .off
            b.widthAnchor.constraint(equalToConstant: (width-4*CGFloat(titles.count-1))/CGFloat(titles.count)).isActive = true
            b.heightAnchor.constraint(equalToConstant: 30).isActive = true
            return b
        }
        return row(buttons, spacing: 4)
    }
    func perform(_ action: WidgetAction) {
        guard !busy, let onAction else { return }; busy = true; actionError = nil; feedbackDetails.isHidden = true
        status.toolTip = nil; status.textColor = config.theme.muted
        rebuild(); status.stringValue = "Applying…"
        onAction(action) { [weak self] error in
            guard let self else { return }; self.busy = false
            self.showFeedback(error)
        }
    }
    private func showFeedback(_ error: String?) {
        actionError = error; rebuild()
        status.stringValue = error ?? ""
        status.textColor = error == nil ? config.theme.muted : config.theme.textAccent(config.theme.red)
        status.toolTip = error
        feedbackDetails.isHidden = error == nil
    }
    private func showActionDetails() {
        guard let actionError, let window else { return }
        ErrorDetailsPresenter.present(actionError, title: "Action needs attention", explanation: "Review the error, then close this message to try the action again.", accessibilityLabel: "Action error details", for: window)
    }
    func openApp(_ id: String) {
        let ids = id == "com.surfshark.vpnclient.macos" ? ["com.surfshark.vpnclient.macos.direct", id] : id == "io.tailscale.ipn.macos" ? ["io.tailscale.ipn.macsys", id] : [id]
        guard let url = ids.compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }).first else { showFeedback("This application is not installed."); return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { [weak self] _, error in
            if let error { DispatchQueue.main.async { self?.showFeedback(error.localizedDescription) } }
        }
    }
    func openURL(_ value: String) { if let url = URL(string: value) { NSWorkspace.shared.open(url) } }

}
