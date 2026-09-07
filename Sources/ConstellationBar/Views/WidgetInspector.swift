import AppKit

final class WidgetInspectorView: OverlayContentView {
    private let kind: WidgetKind
    private var systemState: SystemState
    private let config: BarConfig
    private let metricLabel = NSTextField(labelWithString: "")
    private let historyGraph = SparklineView()
    private var isMetric: Bool { kind == .cpu || kind == .memory }
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let rowsStack = NSStackView()
    private let closeButton = NSButton()
    var onClose: (() -> Void)?

    var preferredSize: NSSize {
        let rowCount = inspectorRows.count
        return NSSize(width: 300, height: 70 + (isMetric ? 140 : 0) + CGFloat(rowCount) * 27 + 14)
    }

    init(kind: WidgetKind, state: SystemState, config: BarConfig, pinned: Bool, history: WidgetHistory = WidgetHistory()) {
        self.kind = kind
        self.systemState = state
        self.config = config
        super.init(frame: .zero)
        applyAppearance(theme: config.theme)

        titleLabel.stringValue = kind.menuTitle
        titleLabel.font = config.appearance.font(size: 13, weight: .semibold)
        titleLabel.textColor = config.theme.foreground
        addSubview(titleLabel)

        subtitleLabel.stringValue = inspectorSubtitle
        subtitleLabel.font = .systemFont(ofSize: 10, weight: .medium)
        subtitleLabel.textColor = config.theme.muted
        subtitleLabel.alignment = .right
        subtitleLabel.lineBreakMode = .byTruncatingTail
        addSubview(subtitleLabel)
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close inspector")
        closeButton.isBordered = false
        closeButton.contentTintColor = config.theme.muted
        closeButton.target = self
        closeButton.action = #selector(closePressed)
        addSubview(closeButton)

        if isMetric {
            metricLabel.font = config.appearance == .porcelain
                ? NSFont(name: "NewYork-Regular", size: 42) ?? NSFont(name: "Georgia", size: 42) ?? .systemFont(ofSize: 42)
                : config.appearance.font(size: 42, weight: .medium)
            metricLabel.textColor = config.theme.foreground
            addSubview(metricLabel)
            historyGraph.color = config.theme.blue
            addSubview(historyGraph)
        }
        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 4
        update(state: state, history: history)
        addSubview(rowsStack)


    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        titleLabel.frame = NSRect(x: 16, y: bounds.height - 34, width: 130, height: 17)
        subtitleLabel.frame = NSRect(x: 148, y: bounds.height - 33, width: bounds.width - 190, height: 15)
        closeButton.frame = NSRect(x: bounds.width - 30, y: bounds.height - 36, width: 18, height: 18)
        metricLabel.frame = NSRect(x: 16, y: bounds.height - 103, width: bounds.width - 32, height: 57)
        historyGraph.frame = NSRect(x: 16, y: bounds.height - 184, width: bounds.width - 32, height: 66)
        rowsStack.frame = NSRect(x: 16, y: 14, width: bounds.width - 32, height: CGFloat(inspectorRows.count) * 27)
    }

    func update(state: SystemState, history: WidgetHistory) {
        systemState = state
        if isMetric {
            let usage = kind == .cpu ? state.cpu.usage : state.memory.usage
            metricLabel.stringValue = "\(Int(usage.rounded()))%"
            historyGraph.values = kind == .cpu ? history.cpu : history.memory
            historyGraph.setAccessibilityLabel("\(kind.menuTitle) utilization history")
            metricLabel.setAccessibilityLabel("\(kind.menuTitle) \(metricLabel.stringValue)")
        }
        rowsStack.arrangedSubviews.forEach { rowsStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        for row in inspectorRows { rowsStack.addArrangedSubview(makeRow(row.0, row.1)) }
        needsLayout = true
    }

    private var inspectorSubtitle: String {
        switch kind {
        case .nowPlaying: return systemState.nowPlaying.source.isEmpty ? "Idle" : systemState.nowPlaying.source
        case .weather: return config.weather.locationLabel
        case .dateTime: return DateFormatter.localizedString(from: systemState.date, dateStyle: .medium, timeStyle: .none)
        default: return "Details"
        }
    }

    private var inspectorRows: [(String, String)] { WidgetCatalog.module(for: kind).rows(systemState, config) }

    private func makeRow(_ title: String, _ value: String) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 268).isActive = true
        row.heightAnchor.constraint(equalToConstant: 23).isActive = true
        let left = NSTextField(labelWithString: title)
        left.font = config.appearance.font(size: 11)
        left.textColor = config.theme.muted
        let right = NSTextField(labelWithString: value)
        right.font = config.appearance.font(size: 11, weight: .medium)
        right.textColor = config.theme.foreground
        right.alignment = .right
        right.lineBreakMode = .byTruncatingMiddle
        row.addSubview(left)
        row.addSubview(right)
        left.frame = NSRect(x: 0, y: 4, width: 112, height: 15)
        right.frame = NSRect(x: 116, y: 4, width: 152, height: 15)
        return row
    }

    @objc private func closePressed() { onClose?() }
}
