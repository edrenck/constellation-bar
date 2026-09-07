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
    private let sampleQueue = DispatchQueue(label: "dev.constellation.sampling", qos: .utility)
    private var timer: Timer?
    private var systemTimer: Timer?
    private var signalSource: DispatchSourceSignal?
    private var latestSystem = SystemState()
    private var latestWorkspace = WorkspaceSnapshot()
    private var refreshInFlight = false
    private var refreshPending = false
    private var sampleInFlight = false
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
    private func sampleSystem() {
        guard !sampleInFlight, !stopped else { return }
        sampleInFlight = true
        var config = self.config
        // A display override can enable modules that are absent from the global layout.
        for override in config.displayOverrides.values where override.enabled != false {
            for kind in override.widgets ?? [] where !config.rightWidgets.contains(kind) { config.rightWidgets.append(kind) }
        }
        let generation = self.generation
        sampleQueue.async { [weak self] in
            guard let self else { return }
            let system = self.systemMonitor.sample(config: config)
            DispatchQueue.main.async {
                self.sampleInFlight = false
                guard !self.stopped else { return }
                if generation == self.generation { self.latestSystem = system }
                else { self.sampleSystem() }
                self.renderCurrentState()
            }
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
                let provider = AeroSpaceClient(binaryPath: config.aerospacePath)
                provider.switchToWorkspace(workspace)
                provider.focusWindow(id)
            }
            DispatchQueue.main.async { self?.requestFocusRefresh() }
        }
    }
    func reorderWidgets(_ kinds: [WidgetKind]) {
        guard kinds != config.rightWidgets else { return }
        config.rightWidgets = kinds
        ConfigurationStore.save(config)
        screenController.apply(config: config)
        onConfigChange?(config)
    }
    func performWidgetAction(_ action: WidgetAction, completion: @escaping (String?) -> Void) {
        if case .authorizeCalendar = action {
            WidgetServices.shared.calendar.requestAccess { [weak self] error in completion(error); self?.sampleSystem() }
            return
        }
        sampleQueue.async { [weak self] in
            var message: String?
            do { try WidgetServices.shared.perform(action) } catch { message = error.localizedDescription }
            DispatchQueue.main.async { completion(message); self?.sampleSystem() }
        }
    }
}

enum IntegrationDiagnostics {
    static let changed = Notification.Name("ConstellationIntegrationsChanged")
    static var workspace = "Checking integrations…" { didSet { NotificationCenter.default.post(name: changed, object: nil) } }
}
