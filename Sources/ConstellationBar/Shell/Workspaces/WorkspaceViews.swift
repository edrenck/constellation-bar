import AppKit
import QuartzCore

final class WorkspaceStripView: NSView {
    private let backdrop = ModernControlView()
    private let stack = NSStackView()
    private let selection = NSView()
    private var selectionName: String?
    private var hasSelectionFrame = false
    private var pendingSelection: String?
    private var selectionRequest = 0
    private let overflow = NSButton(title: "…", target: nil, action: nil)
    private var allWorkspaces: [WorkspaceState] = []
    var composition: BarLayout = .islands { didSet { backdrop.isHidden = composition == .rail; controls.values.forEach { $0.composition = composition } } }
    private var controls: [String: WorkspaceControlView] = [:]
    private var theme = BarTheme.dark
    private var visuals = VisualPreferences()
    var onWorkspaceClick: ((String) -> Void)?
    var onWorkspaceHover: ((WorkspaceState, WorkspaceControlView, Bool) -> Void)?

    var preferredWidth: CGFloat {
        let spacing = max(0, CGFloat(max(0, controls.count - 1)) * stack.spacing)
        return controls.isEmpty ? 0 : max(56, controls.values.reduce(CGFloat(12)) { $0 + $1.preferredWidth } + spacing)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(backdrop)
        selection.wantsLayer = true
        selection.setAccessibilityElement(false)
        addSubview(selection)
        stack.orientation = .horizontal
        stack.spacing = 3
        stack.alignment = .centerY
        addSubview(stack)
        overflow.bezelStyle = .texturedRounded
        overflow.target = self
        overflow.action = #selector(showOverflow)
        overflow.setAccessibilityLabel("All workspaces")
        overflow.isHidden = true
        addSubview(overflow)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        backdrop.frame = bounds
        stack.frame = bounds.insetBy(dx: 6, dy: 3)
        overflow.frame = bounds.insetBy(dx: 6, dy: 3)
        stack.layoutSubtreeIfNeeded()
        updateSelectionFrame()

    }

    private func updateSelectionFrame() {
        guard !stack.isHidden, let control = controls.values.first(where: { $0.workspace.isFocused }), control.bounds.width > 0 else {
            selection.isHidden = true; hasSelectionFrame = false; return
        }
        let name = control.workspace.name
        var target = control.convert(control.bounds, to: self)
        if theme.appearanceID == .typeset { target = NSRect(x: target.minX + 5, y: target.minY, width: max(0, target.width - 10), height: 2) }
        guard let layer = selection.layer else { return }
        let oldPosition = layer.presentation()?.position ?? layer.position
        let oldBounds = layer.presentation()?.bounds ?? layer.bounds
        let animate = hasSelectionFrame && selectionName != name && window?.isVisible == true && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && !ModernControlView.rendersOpaqueMaterials
        CATransaction.begin(); CATransaction.setDisableActions(true)
        selection.isHidden = false
        selection.frame = target
        layer.backgroundColor = (theme.appearanceID == .typeset ? theme.blue : theme.selectionFill).cgColor
        layer.cornerRadius = theme.appearanceID == .typeset ? 1 : theme.appearanceID.selectionRadius
        CATransaction.commit()
        if animate {
            let position = CABasicAnimation(keyPath: "position"); position.fromValue = oldPosition; position.toValue = layer.position
            let size = CABasicAnimation(keyPath: "bounds"); size.fromValue = oldBounds; size.toValue = layer.bounds
            let motion = CAAnimationGroup(); motion.animations = [position, size]; motion.duration = 0.16
            motion.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(motion, forKey: "workspaceSelection")
        } else if selectionName != name || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { layer.removeAnimation(forKey: "workspaceSelection") }
        selectionName = name; hasSelectionFrame = true
    }

    func apply(theme: BarTheme) {
        self.theme = theme
        backdrop.isHidden = composition == .rail
        backdrop.theme = theme
        backdrop.updateAppearance()
        controls.values.forEach { $0.apply(theme: theme) }
    }

    func apply(visuals: VisualPreferences) {
        self.visuals = visuals
        backdrop.apply(visuals: visuals)
        controls.values.forEach { $0.apply(visuals: visuals) }
        stack.spacing = visuals.density == .spacious ? 5 : 3
        needsLayout = true
    }

    func update(workspaces: [WorkspaceState], theme: BarTheme) {
        allWorkspaces = workspaces
        if let pendingSelection, workspaces.first(where: { $0.isFocused })?.name == pendingSelection || !workspaces.contains(where: { $0.name == pendingSelection }) { self.pendingSelection = nil }
        let displayWorkspaces = workspaces.map { workspace -> WorkspaceState in
            var value = workspace
            if let pendingSelection { value.isFocused = value.name == pendingSelection }
            return value
        }
        let names = workspaces.map(\.name)
        if names != stack.arrangedSubviews.compactMap({ ($0 as? WorkspaceControlView)?.workspace.name }) {
            stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
            controls.removeAll()
            for workspace in workspaces {
                let control = WorkspaceControlView(workspace: workspace)
                control.selectionInStrip = true
                control.composition = composition
                control.apply(visuals: visuals)
                control.onClick = { [weak self] name in self?.requestSelection(name) }
                control.onWorkspaceHover = { [weak self, weak control] state, entered in
                    guard let self, let control else { return }
                    self.onWorkspaceHover?(state, control, entered)
                }
                controls[workspace.name] = control
                stack.addArrangedSubview(control)
                control.installWidthConstraint()
            }
        }
        for workspace in displayWorkspaces { controls[workspace.name]?.update(workspace: workspace, theme: theme) }
        apply(theme: theme)
        needsLayout = true
    }
    func fit(to width: CGFloat) {
        let collapsed = preferredWidth > width
        stack.isHidden = collapsed
        selection.isHidden = collapsed
        needsLayout = true
        overflow.isHidden = !collapsed
        overflow.title = (allWorkspaces.first { $0.isFocused }.map { $0.displayName ?? $0.name } ?? "Spaces") + " ▾"
    }
    private func requestSelection(_ name: String) {
        pendingSelection = name; selectionRequest += 1
        let request = selectionRequest
        update(workspaces: allWorkspaces, theme: theme)
        superview?.needsLayout = true
        superview?.layoutSubtreeIfNeeded()
        layoutSubtreeIfNeeded()
        onWorkspaceClick?(name)
        // A failed switch must not leave an optimistic highlight stuck forever.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.selectionRequest == request, self.pendingSelection != nil else { return }
            self.pendingSelection = nil
            self.update(workspaces: self.allWorkspaces, theme: self.theme)
        }
    }
    @objc private func showOverflow() {
        let menu = NSMenu()
        for workspace in allWorkspaces {
            let item = NSMenuItem(title: workspace.displayName ?? workspace.name, action: #selector(selectWorkspace(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = workspace.name
            item.state = workspace.isFocused ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.minY), in: self)
    }
    @objc private func selectWorkspace(_ sender: NSMenuItem) {
        if let name = sender.representedObject as? String { requestSelection(name) }
    }

}

final class WorkspaceControlView: ModernControlView {
    var selectionInStrip = false
    var composition: BarLayout = .islands { didSet { updateAppearance(); needsLayout = true } }
    private let label = NSTextField(labelWithString: "")
    fileprivate var workspace: WorkspaceState
    private let appIconStack = NSStackView()
    private var widthConstraint: NSLayoutConstraint?
    private var displayedApps: [AppIdentity] = []
    var onClick: ((String) -> Void)?
    var onWorkspaceHover: ((WorkspaceState, Bool) -> Void)?

    var preferredWidth: CGFloat {
        let base = max(35, min(120, ceil(label.intrinsicContentSize.width) + 18))
        guard visualPreferences.showsWorkspaceAppIcons, composition != .compact else { return base }
        return base + CGFloat(min(3, workspace.apps.count)) * 17
    }

    init(workspace: WorkspaceState) {
        self.workspace = workspace
        super.init(frame: .zero)
        setMaterialVisible(false)
        label.alignment = .center
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        addSubview(label)
        appIconStack.orientation = .horizontal
        appIconStack.alignment = .centerY
        appIconStack.spacing = 3
        addSubview(appIconStack)
        onHoverChanged = { [weak self] entered in
            guard let self else { return }
            self.onWorkspaceHover?(self.workspace, entered)
        }
        keyboardAction = { [weak self] in guard let self else { return }; self.onClick?(self.workspace.name) }
        setAccessibilityRole(.button)
        setAccessibilityElement(true)
        update(workspace: workspace, theme: .dark)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        if visualPreferences.showsWorkspaceAppIcons, !displayedApps.isEmpty {
            let labelWidth = max(20, min(106, label.intrinsicContentSize.width))
            label.frame = NSRect(x: 6, y: bounds.midY - 8, width: labelWidth, height: 16)
            appIconStack.frame = NSRect(x: labelWidth + 12, y: bounds.midY - 7, width: max(0, bounds.width - labelWidth - 18), height: 14)
        } else {
            label.frame = NSRect(x: 2, y: bounds.midY - 8, width: bounds.width - 4, height: 16)
            appIconStack.frame = .zero
        }

    }

    func apply(theme: BarTheme) { update(workspace: workspace, theme: theme) }

    override func apply(visuals: VisualPreferences) {
        super.apply(visuals: visuals)
        rebuildAppIcons()
        widthConstraint?.constant = preferredWidth
    }

    func update(workspace: WorkspaceState, theme: BarTheme) {
        self.workspace = workspace
        self.theme = theme
        label.stringValue = workspace.displayName ?? workspace.name
        setAccessibilityLabel("Workspace \(label.stringValue), \(workspace.windows.count) windows")
        setAccessibilityValue(workspace.isFocused ? "Selected" : "")
        toolTip = "\(workspace.name) · \(workspace.windows.count) windows"
        rebuildAppIcons()
        updateAppearance()
    }

    func installWidthConstraint() {
        widthConstraint?.isActive = false
        widthConstraint = widthAnchor.constraint(equalToConstant: preferredWidth)
        widthConstraint?.isActive = true
    }

    private func rebuildAppIcons() {
        let apps = visualPreferences.showsWorkspaceAppIcons && composition != .compact ? Array(workspace.apps.prefix(3)) : []
        guard apps != displayedApps else { return }
        displayedApps = apps
        appIconStack.arrangedSubviews.forEach { appIconStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        for app in apps {
            let icon = NSImageView(image: AppIconProvider.icon(for: app))
            icon.imageScaling = .scaleProportionallyUpOrDown
            icon.setAccessibilityLabel(app.name)
            icon.widthAnchor.constraint(equalToConstant: 14).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 14).isActive = true
            appIconStack.addArrangedSubview(icon)
        }
        widthConstraint?.constant = preferredWidth
        needsLayout = true
    }

    override func updateAppearance() {
        guard label.superview != nil else { return }
        setMaterialVisible(false)
        let focused = workspace.isFocused
        let style = theme.appearanceID
        let title = workspace.displayName ?? workspace.name
        label.stringValue = style == .typeset && focused ? "[\(title)]" : title
        label.font = style.font(size: 12, weight: focused ? .semibold : .regular)
        label.textColor = focused ? theme.selectionText : workspace.windows.isEmpty ? theme.muted : theme.foreground
        setFillColor(focused ? (selectionInStrip ? .clear : theme.selectionFill) : isHovered ? theme.surfaceStrong : .clear)
        cornerRadiusOverride = style.selectionRadius
        layer?.borderWidth = (focused || isHovered) && NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 1 : 0
        layer?.borderColor = theme.foreground.cgColor
        layer?.shadowOpacity = 0
        widthConstraint?.constant = preferredWidth
        needsLayout = true
    }

    override func mouseDown(with event: NSEvent) {
        onClick?(workspace.name)
    }
}

final class ActiveWindowControl: ModernControlView {
    var composition: BarLayout = .islands { didSet { updateAppearance() } }
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "Desktop")
    private var displayedIdentity: String?
    var onClick: ((ActiveWindowControl) -> Void)?

    var preferredWidth: CGFloat {
        min(300, max(126, ceil(titleLabel.intrinsicContentSize.width) + 62))
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setMaterialVisible(true)
        iconView.wantsLayer = true
        titleLabel.wantsLayer = true
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)
        keyboardAction = { [weak self] in guard let self else { return }; self.onClick?(self) }
        setAccessibilityRole(.button)
        setAccessibilityLabel("Active application and window switcher")

    }

    override func updateAppearance() {
        setMaterialVisible(composition != .rail)
        super.updateAppearance()
        if composition == .rail {
            setFillColor(isHovered ? theme.surfaceStrong : .clear)
            layer?.borderWidth = 0
            layer?.shadowOpacity = 0
        }
        titleLabel.font = theme.appearanceID.font(size: 12, weight: .medium)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        iconView.frame = NSRect(x: 10, y: bounds.midY - 8, width: 16, height: 16)
        titleLabel.frame = NSRect(x: 33, y: bounds.midY - 8, width: max(0, bounds.width - 43), height: 17)
    }

    func apply(theme: BarTheme) {
        self.theme = theme
        titleLabel.textColor = theme.foreground
        updateAppearance()
    }

    func update(window: WindowIdentity?, theme: BarTheme) {
        apply(theme: theme)
        let title = window?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let appName = window?.appName ?? "Desktop"
        let normalizedTitle = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let normalizedAppName = appName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let duplicate = normalizedTitle == normalizedAppName || normalizedTitle.hasPrefix(normalizedAppName + " —")
        let displayTitle = title.isEmpty || duplicate ? appName : "\(appName) — \(title)"
        let identity = (window?.bundleID ?? "") + "|" + displayTitle
        guard identity != displayedIdentity else { return }
        if displayedIdentity != nil && self.window?.isVisible == true && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && !ModernControlView.rendersOpaqueMaterials {
            for view in [iconView as NSView, titleLabel] {
                let fade = CATransition(); fade.type = .fade; fade.duration = 0.20
                fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                view.layer?.add(fade, forKey: "activeApplication")
            }
        }
        displayedIdentity = identity
        titleLabel.stringValue = displayTitle
        iconView.image = window.map { AppIconProvider.icon(for: $0.appIdentity) } ?? NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: "Desktop")
        setAccessibilityValue(displayTitle)
        needsLayout = true
    }

    override func mouseDown(with event: NSEvent) { onClick?(self) }
}
