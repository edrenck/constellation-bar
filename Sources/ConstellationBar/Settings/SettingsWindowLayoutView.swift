import AppKit

/// Window geometry owns navigation/recovery placement, independently of settings transactions.
final class SettingsWindowLayoutView: NSVisualEffectView {
    private let navigation: NSView
    private let compactNavigation: NSView
    private var wideConstraints: [NSLayoutConstraint] = []
    private var compactConstraints: [NSLayoutConstraint] = []
    private(set) var isCompact = false
    private(set) var isShort = false
    var onModeChanged: ((Bool) -> Void)?

    init(navigation: NSView, compactNavigation: NSView, form: NSView, recovery: NSView) {
        self.navigation = navigation; self.compactNavigation = compactNavigation
        super.init(frame: .zero)
        material = .sidebar; blendingMode = .behindWindow; state = .active
        for view in [navigation, compactNavigation, form, recovery] {
            view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view)
        }
        compactNavigation.isHidden = true
        NSLayoutConstraint.activate([
            recovery.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            recovery.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            recovery.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            form.trailingAnchor.constraint(equalTo: trailingAnchor),
            form.bottomAnchor.constraint(equalTo: recovery.topAnchor, constant: -12)
        ])
        wideConstraints = [
            navigation.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            navigation.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            navigation.bottomAnchor.constraint(equalTo: form.bottomAnchor, constant: -4),
            navigation.widthAnchor.constraint(equalToConstant: 190),
            form.leadingAnchor.constraint(equalTo: navigation.trailingAnchor, constant: 16),
            form.topAnchor.constraint(equalTo: topAnchor)
        ]
        compactConstraints = [
            compactNavigation.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            compactNavigation.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            compactNavigation.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            form.leadingAnchor.constraint(equalTo: leadingAnchor),
            form.topAnchor.constraint(equalTo: compactNavigation.bottomAnchor, constant: 10)
        ]
        NSLayoutConstraint.activate(wideConstraints)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func layout() {
        if bounds.width > 0, bounds.height > 0 {
            let short = bounds.height < 560
            let compact = bounds.width < 860 || short
            if compact != isCompact || short != isShort {
                let focused = window?.firstResponder as? NSView
                let navigationHadFocus = focused?.isDescendant(of: navigation) == true || focused?.isDescendant(of: compactNavigation) == true
                if compact != isCompact {
                    NSLayoutConstraint.deactivate(isCompact ? compactConstraints : wideConstraints)
                    NSLayoutConstraint.activate(compact ? compactConstraints : wideConstraints)
                }
                isCompact = compact; isShort = short
                navigation.isHidden = compact; compactNavigation.isHidden = !compact
                onModeChanged?(navigationHadFocus)
            }
        }
        super.layout()
    }
}

/// Save recovery remains visible while the form and navigation scroll independently.
final class SettingsRecoveryView: NSStackView {
    private let actions: NSStackView
    init(status: NSTextField, buttons: [NSButton]) {
        actions = NSStackView(views: buttons)
        super.init(frame: .zero)
        orientation = .vertical; alignment = .leading; spacing = 8
        actions.orientation = .horizontal; actions.alignment = .centerY; actions.spacing = 8
        addArrangedSubview(status); addArrangedSubview(actions)
        status.translatesAutoresizingMaskIntoConstraints = false
        status.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        status.maximumNumberOfLines = 2
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    override func layout() {
        let direction: NSUserInterfaceLayoutOrientation = bounds.width > 0 && bounds.width < 450 ? .vertical : .horizontal
        if actions.orientation != direction { actions.orientation = direction; actions.alignment = direction == .vertical ? .leading : .centerY }
        super.layout()
    }
}
