import AppKit

/// Owns list-choice identity, selection and asynchronous discovery presentation.
/// The runtime supplies values; this view never accesses EventKit or writes reminders.
final class ReminderListSettingsView: NSStackView {
    typealias ReadLists = (@escaping (Result<ReminderListSnapshot, WidgetActionError>) -> Void) -> Void
    private let read: ReadLists
    private var snapshot: ReminderListSnapshot?
    private var selectedIDs: Set<String> = []
    private var failure: String?
    private var refreshPending = false
    private(set) var isLoading = false
    private(set) var buttons: [String: NSButton] = [:]
    let allowButton = NSButton(title: "Allow Reminders access…", target: nil, action: nil)
    let status = NSTextField(wrappingLabelWithString: "Checking Reminders access…")
    let refreshButton = NSButton(title: "Refresh lists", target: nil, action: nil)
    var onSelection: (([String]) -> Void)?
    var onAuthorize: (() -> Void)?

    init(read: @escaping ReadLists) {
        self.read = read
        super.init(frame: .zero)
        orientation = .vertical; alignment = .leading; spacing = 8
        status.textColor = .secondaryLabelColor
        addArrangedSubview(allowButton); addArrangedSubview(status); addArrangedSubview(refreshButton)
        allowButton.target = self; allowButton.action = #selector(authorize)
        status.translatesAutoresizingMaskIntoConstraints = false
        status.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        refreshButton.target = self; refreshButton.action = #selector(refresh)
        refreshButton.setAccessibilityLabel("Refresh Reminders list choices")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func sync(selectedIDs: [String]) { self.selectedIDs = Set(selectedIDs); render() }

    @objc func refresh() {
        // Collapse invalidations during a read into one follow-up. Discard the older value.
        if isLoading { refreshPending = true; return }
        isLoading = true; render()
        read { [weak self] result in
            guard let self else { return }
            dispatchPrecondition(condition: .onQueue(.main))
            self.isLoading = false
            if self.refreshPending {
                self.refreshPending = false; self.refresh(); return
            }
            switch result {
            case let .success(snapshot): self.snapshot = snapshot; self.failure = nil
            case let .failure(error): self.snapshot = nil; self.failure = error.localizedDescription
            }
            self.render()
        }
    }

    private func render() {
        let focus = PanelFocus(body: self, window: window)
        let lists = snapshot?.lists ?? []
        var titles: [String: String] = [:], ids: [String] = []
        if snapshot?.authorized == true {
            for list in lists where titles[list.id] == nil { ids.append(list.id); titles[list.id] = list.title }
            let missing = selectedIDs.subtracting(ids).sorted()
            for (index, id) in missing.enumerated() {
                ids.append(id); titles[id] = "Unavailable selected list" + (missing.count > 1 ? " \(index + 1)" : "")
            }
        }
        for id in Array(buttons.keys) where !ids.contains(id) {
            if let button = buttons.removeValue(forKey: id) { removeArrangedSubview(button); button.removeFromSuperview() }
        }
        let availableIDs = Set(lists.map(\.id))
        for (index, id) in ids.enumerated() {
            let button = buttons[id] ?? NSButton(checkboxWithTitle: "", target: self, action: #selector(selectionChanged))
            buttons[id] = button
            button.title = titles[id] ?? "Untitled list"
            button.identifier = NSUserInterfaceItemIdentifier("reminders.settings.list.\(id)")
            button.setAccessibilityLabel(button.title)
            button.toolTip = availableIDs.contains(id) ? nil : "This selected list is not available on this Mac. Uncheck it to remove it from your selection."
            button.state = selectedIDs.contains(id) ? .on : .off
            if !arrangedSubviews.contains(where: { $0 === button }) { insertArrangedSubview(button, at: index) }
            else if arrangedSubviews.firstIndex(where: { $0 === button }) != index {
                removeArrangedSubview(button); insertArrangedSubview(button, at: index)
            }
        }
        refreshButton.isEnabled = !isLoading
        allowButton.isHidden = snapshot?.authorized != false || failure != nil
        allowButton.isEnabled = !isLoading
        status.textColor = failure == nil ? .secondaryLabelColor : .systemOrange
        if isLoading { status.stringValue = "Refreshing reminder lists…" }
        else if let failure { status.stringValue = "Couldn’t load reminder lists. \(failure) Try Refresh lists." }
        else if snapshot?.authorized == true {
            status.stringValue = lists.isEmpty
                ? "No reminder lists are available on this Mac. Create or sync a list in Reminders, then refresh."
                : "Choose the lists to show. Leave every list unchecked to show all lists. No reminders are edited."
            if !selectedIDs.subtracting(availableIDs).isEmpty {
                status.stringValue += " Unavailable selections are kept until you uncheck them."
            }
        } else { status.stringValue = "Press Allow to grant Reminders access. Lists and due tasks are read from this Mac; no reminders are edited." }
        window?.contentView?.needsLayout = true
        focus?.restore(body: self, window: window, fallback: refreshButton)
    }

    @objc private func selectionChanged() {
        onSelection?(buttons.filter { $0.value.state == .on }.map(\.key).sorted())
    }
    @objc private func authorize() { onAuthorize?() }
}
