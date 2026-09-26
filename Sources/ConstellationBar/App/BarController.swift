import AppKit

/// UI/configuration state is owned by the main queue; provider work uses immutable snapshots.
final class BarController {
    private var config: BarConfig
    private let systemMonitor = SystemMonitor()
    private let screenController: ScreenBarController
    private let workspaceQueue = DispatchQueue(label: "dev.constellation.workspace", qos: .userInitiated)
    private let focusQueue = DispatchQueue(label: "dev.constellation.focus", qos: .userInitiated)
    private var focusInFlight = false
    private var focusPending = false
    private var focusRevision = 0
    private let workspaceActionQueue = DispatchQueue(label: "dev.constellation.workspace-actions", qos: .userInitiated)
    private var timer: Timer?
    private var systemTimer: Timer?
    private var signalSource: DispatchSourceSignal?
    private var latestSystem = SystemState()
    private var latestWorkspace = WorkspaceSnapshot()
    private var refreshInFlight = false
    private var refreshPending = false
    private var stopped = false
    private var generation = 0
    private var appearanceObservation: NSKeyValueObservation?
    var onConfigChange: ((BarConfig) -> Void)?

    init(config: BarConfig) {
        self.config = config
        screenController = ScreenBarController(config: config)
        screenController.interactionDelegate = self
    }
    func apply(config: BarConfig) {
        self.config = config
        generation += 1
        screenController.apply(config: config)
        installTimers()
        sampleSystem()
        requestRefresh()
    }
    func start() {
        signal(SIGUSR1, SIG_IGN)
        signalSource = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        signalSource?.setEventHandler { [weak self] in self?.requestFocusRefresh() }
        signalSource?.resume()
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refreshAppearance() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refreshAppearance), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        screenController.installBars()
        sampleSystem()
        requestRefresh()
        installTimers()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshDiagnostics), name: IntegrationDiagnostics.refreshRequested, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(workspaceChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(workspaceChanged), name: NSWorkspace.didWakeNotification, object: nil)
    }
    private func installTimers() {
        timer?.invalidate()
        systemTimer?.invalidate()
        timer = Timer(timeInterval: config.updateInterval, repeats: true) { [weak self] _ in self?.requestRefresh() }
        systemTimer = Timer(timeInterval: config.systemUpdateInterval, repeats: true) { [weak self] _ in self?.sampleSystem() }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        if let systemTimer { RunLoop.main.add(systemTimer, forMode: .common) }
    }
    func stop() {
        stopped = true
        appearanceObservation = nil
        timer?.invalidate()
        systemTimer?.invalidate()
        signalSource?.cancel()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        systemMonitor.stop()
        screenController.closeBars()
    }
    @objc private func refreshAppearance() { screenController.apply(config: config); renderCurrentState(); onConfigChange?(config) }
    @objc private func screenParametersChanged() { screenController.installBars(); requestRefresh() }
    @objc private func workspaceChanged() { requestFocusRefresh() }

    // Keyboard callbacks get a single focused-space query on their own queue.
    // Full window enumeration must not delay the selection highlight.
    private func requestFocusRefresh() {
        guard !stopped else { return }
        guard config.integration != .standalone else { requestRefresh(); return }
        guard !focusInFlight else { focusPending = true; return }
        focusInFlight = true
        let config = self.config, generation = self.generation
        focusQueue.async { [weak self] in
            let name = AeroSpaceClient(binaryPath: config.aerospacePath).focusedWorkspace()
            DispatchQueue.main.async {
                guard let self else { return }
                self.focusInFlight = false
                guard !self.stopped else { return }
                if generation == self.generation, let name, self.latestWorkspace.workspaces.contains(where: { $0.name == name }) {
                    self.focusRevision += 1
                    for index in self.latestWorkspace.workspaces.indices { self.latestWorkspace.workspaces[index].isFocused = self.latestWorkspace.workspaces[index].name == name }
                    self.renderCurrentState()
                }
                self.requestRefresh()
                if self.focusPending { self.focusPending = false; self.requestFocusRefresh() }
            }
        }
    }

    func requestRefresh() {
        guard !stopped else { return }
        guard !refreshInFlight else { refreshPending = true; return }
        refreshInFlight = true
        let config = self.config, generation = self.generation, focusRevision = self.focusRevision
        workspaceQueue.async { [weak self] in
            var snapshot: WorkspaceSnapshot
            if config.integration == .standalone {
                snapshot = StandaloneWorkspaceProvider().snapshot(config: config)
            } else {
                snapshot = AeroSpaceClient(binaryPath: config.aerospacePath).snapshot(config: config)
                if snapshot.status != "AeroSpace connected", config.integration == .automatic {
                    let reason = snapshot.status
                    snapshot = StandaloneWorkspaceProvider().snapshot(config: config)
                    snapshot.status = "Standalone · \(reason)"
                }
            }
            DispatchQueue.main.async {
                guard let self, !self.stopped else { return }
                if generation == self.generation {
                    if focusRevision != self.focusRevision {
                        let focused = self.latestWorkspace.workspaces.first(where: { $0.isFocused })?.name
                        for index in snapshot.workspaces.indices { snapshot.workspaces[index].isFocused = snapshot.workspaces[index].name == focused }
                        snapshot.focusedWindow = self.latestWorkspace.focusedWindow
                    }
                    self.latestWorkspace = snapshot
                    IntegrationDiagnostics.workspace = snapshot.status
                    self.renderCurrentState()
                }
                self.refreshInFlight = false
                if self.refreshPending { self.refreshPending = false; self.requestRefresh() }
            }
        }
    }
    @objc private func refreshDiagnostics() { sampleSystem(); requestRefresh() }

    private func sampleSystem() {
        guard !stopped else { return }
        var config = self.config
        config.rightWidgets = config.widgetsForSampling
        let generation = self.generation
        systemMonitor.refresh(config: config, generation: generation) { [weak self] system in
            guard let self, !self.stopped, generation == self.generation else { return }
            self.latestSystem = system
            IntegrationDiagnostics.publish(system, config: config, sampledKinds: self.systemMonitor.sampledKinds)
            self.renderCurrentState()
        }
    }
    private func renderCurrentState() {
        var system = latestSystem
        system.date = Date()
        screenController.render(state: BarState(workspaces: latestWorkspace.workspaces, focusedWindow: latestWorkspace.focusedWindow, system: system, providerStatus: latestWorkspace.status))
    }
}

extension BarController: BarInteractionDelegate {
    func switchToWorkspace(_ name: String) {
        let config = self.config
        workspaceActionQueue.async { [weak self] in
            AeroSpaceClient(binaryPath: config.aerospacePath).switchToWorkspace(name)
            DispatchQueue.main.async { self?.requestFocusRefresh() }
        }
    }
    func focusWindow(_ id: Int, workspace: String) {
        let config = self.config
        workspaceActionQueue.async { [weak self] in
            if workspace.isEmpty { StandaloneWorkspaceProvider().focusWindow(id) }
            else {
                // AeroSpace focuses the window's workspace as part of focusing
                // its ID. A separate workspace switch focuses an intermediate
                // window and doubles the CLI round trips for one selection.
                AeroSpaceClient(binaryPath: config.aerospacePath).focusWindow(id)
            }
            DispatchQueue.main.async { self?.requestFocusRefresh() }
        }
    }
    func reorderWidgets(_ kinds: [WidgetKind], displayID: String?, zone: BarZone) {
        var config = self.config
        if let displayID {
            var override = config.displayOverrides[displayID] ?? DisplayOverride()
            var layout = override.widgetLayout ?? config.forDisplay(displayID).widgetLayout
            let existing = layout.items(in: zone)
            var reordered = kinds.makeIterator()
            let replacement = existing.map { item in
                item.widgetKind.map { kinds.contains($0) } == true ? BarItem.widget(reordered.next()!) : item
            }
            layout.setItems(replacement, in: zone)
            override.widgetLayout = layout
            config.displayOverrides[displayID] = override
        } else {
            var layout = config.widgetLayout
            let existing = layout.items(in: zone)
            var reordered = kinds.makeIterator()
            let replacement = existing.map { item in
                item.widgetKind.map { kinds.contains($0) } == true ? BarItem.widget(reordered.next()!) : item
            }
            layout.setItems(replacement, in: zone)
            config.setWidgetLayout(layout)
        }
        guard ConfigurationStore.save(config) else { return }
        self.config = config
        screenController.apply(config: config)
        onConfigChange?(config)
    }
    func performWidgetAction(_ action: WidgetAction, completion: @escaping (String?) -> Void) {
        if case .authorizeMusic = action {
            AppleMusicIntegration.requestAccess { [weak self] error in completion(error); self?.sampleSystem() }
            return
        }
        if case .authorizeReminders = action {
            let done: (String?) -> Void = { [weak self] error in completion(error); self?.sampleSystem() }
            systemMonitor.perform(kind: .reminders, operation: {
                WidgetServices.shared.reminders.requestAccess(completion: done)
            }) { error in if let error { completion(error) } }
            return
        }
        if case .authorizeCalendar = action {
            let selected = config.providerPreferences.calendarProvider
            guard config.providerPreferences.includes(selected.rawValue) else { completion("Enable the provider in Customize Bar → Widgets → Calendar first."); return }
            let done: (String?) -> Void = { [weak self] error in completion(error); self?.sampleSystem() }
            systemMonitor.perform(kind: .calendar, operation: {
                if selected == .outlook { WidgetServices.shared.outlook.requestAccess(completion: done) }
                else { WidgetServices.shared.calendar.requestAccess(completion: done) }
            }) { error in if let error { completion(error) } }
            return
        }
        systemMonitor.perform(kind: action.providerKind, operation: { try WidgetServices.shared.perform(action) }) { [weak self] message in
            completion(message); self?.sampleSystem()
        }
    }
}
