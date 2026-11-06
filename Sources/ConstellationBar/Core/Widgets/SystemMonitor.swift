import Foundation

/// Each provider and its adapters belong to one serial queue. Its snapshots are
/// merged on the main queue as soon as they arrive, without waiting for peers.
protocol SystemProviding: AnyObject {
    var kinds: Set<WidgetKind> { get }
    func sample(config: BarConfig, into state: inout SystemState)
    func merge(snapshot: SystemState, into state: inout SystemState)
    func deactivate()
}
extension SystemProviding {
    func deactivate() {}
    func merge(snapshot: SystemState, into state: inout SystemState) {
        if kinds.contains(.battery) { state.battery = snapshot.battery }
        if !kinds.isDisjoint(with: [.system, .network, .cpu, .memory, .disk, .uptime, .thermal]) {
            state.network = snapshot.network; state.cpu = snapshot.cpu; state.memory = snapshot.memory
            state.disk = snapshot.disk; state.uptime = snapshot.uptime; state.thermal = snapshot.thermal
            state.topProcesses = snapshot.topProcesses
            state.topProcessesStatus = snapshot.topProcessesStatus
            state.metricsSampledAt = snapshot.metricsSampledAt
        }
        if kinds.contains(.vpn) { state.vpn = snapshot.vpn }
        if kinds.contains(.nowPlaying) { state.nowPlaying = snapshot.nowPlaying; state.mediaSessions = snapshot.mediaSessions }
        if kinds.contains(.weather) { state.weather = snapshot.weather }
        if kinds.contains(.audio) { state.audio = snapshot.audio }
        if kinds.contains(.calendar) { state.agenda = snapshot.agenda }
        if kinds.contains(.agentStatus) { state.agents = snapshot.agents }
        state.providerStatuses += snapshot.providerStatuses
    }
}
final class SystemMonitor {
    private final class Slot {
        let provider: SystemProviding
        let queue: DispatchQueue
        let lock = NSLock()
        private var revision: Int?
        private var stopped = false
        var enabled = false
        var inFlight = false
        var pending = false
        var snapshot: SystemState?
        init(_ provider: SystemProviding, index: Int) {
            self.provider = provider
            queue = DispatchQueue(label: "dev.constellation.provider.\(index)", qos: .userInitiated)
        }
        func setRevision(_ value: Int?) { lock.lock(); revision = value; lock.unlock() }
        var isDisabled: Bool { lock.lock(); defer { lock.unlock() }; return revision == nil }
        func accepts(_ value: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return revision == value }
        func stop() { lock.lock(); revision = nil; stopped = true; lock.unlock() }
        var allowsSetup: Bool { lock.lock(); defer { lock.unlock() }; return !stopped }
    }
    private let slots: [Slot]
    private var config = BarConfig.default
    private var generation: Int?
    private var update: ((SystemState) -> Void)?
    private var stopped = false
    init(providers: [SystemProviding]) {
        slots = providers.enumerated().map { Slot($0.element, index: $0.offset) }
    }
    /// Synchronous diagnostics use the same ownership boundary as live sampling.
    func sample(config: BarConfig) -> SystemState {
        var state = SystemState()
        let enabled = Set(config.rightWidgets)
        for slot in slots where !slot.provider.kinds.isDisjoint(with: enabled) {
            let snapshot = slot.queue.sync { () -> SystemState in
                var snapshot = SystemState(); slot.provider.sample(config: config, into: &snapshot); return snapshot
            }
            slot.provider.merge(snapshot: snapshot, into: &state)
        }
        return state
    }
    func refresh(config: BarConfig, generation: Int, onUpdate: @escaping (SystemState) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !stopped else { return }
        self.config = config; update = onUpdate
        let changed = self.generation != generation
        self.generation = generation
        let enabled = Set(config.rightWidgets)
        for slot in slots {
            let active = !slot.provider.kinds.isDisjoint(with: enabled)
            let wasEnabled = slot.enabled
            slot.enabled = active
            slot.setRevision(active ? generation : nil)
            if wasEnabled && !active { deactivate(slot) }
            if changed || !active { slot.snapshot = nil }
            guard active else { slot.pending = false; continue }
            if slot.inFlight { slot.pending = true } else { schedule(slot) }
        }
        if changed { publish() }
    }
    var sampledKinds: Set<WidgetKind> {
        Set(slots.filter { $0.snapshot != nil }.flatMap { $0.provider.kinds })
    }
    func requestSample(kind: WidgetKind, completion: (String?) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let generation, let slot = slots.first(where: { $0.provider.kinds.contains(kind) }), slot.accepts(generation) else {
            completion("Enable this widget before refreshing it."); return
        }
        if slot.inFlight { slot.pending = true } else { schedule(slot) }
        completion(nil)
    }
    /// Local presentation work must not restart external reads or change their cadence.
    func requestSamples(kinds: Set<WidgetKind>) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let generation else { return }
        for slot in slots where !slot.provider.kinds.isDisjoint(with: kinds) && slot.accepts(generation) {
            if slot.inFlight { slot.pending = true } else { schedule(slot) }
        }
    }
    private func deactivate(_ slot: Slot) {
        slot.queue.async { if slot.isDisabled { slot.provider.deactivate() } }
    }
    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !stopped else { return }
        stopped = true
        generation = nil; update = nil
        for slot in slots {
            slot.stop(); slot.pending = false; slot.snapshot = nil
            if slot.enabled { slot.enabled = false; deactivate(slot) }
        }
    }
    private func schedule(_ slot: Slot) {
        guard let generation, slot.accepts(generation) else { return }
        slot.inFlight = true; slot.pending = false
        let config = self.config
        slot.queue.async { [weak self] in
            var snapshot: SystemState?
            if slot.accepts(generation) {
                var result = SystemState(); slot.provider.sample(config: config, into: &result); snapshot = result
            }
            DispatchQueue.main.async {
                guard let self else { return }
                slot.inFlight = false
                if self.generation == generation, slot.accepts(generation), let snapshot {
                    slot.snapshot = snapshot; self.publish()
                }
                if slot.pending { self.schedule(slot) }
            }
        }
    }
    private func publish() {
        var state = SystemState()
        for slot in slots { if let snapshot = slot.snapshot { slot.provider.merge(snapshot: snapshot, into: &state) } }
        update?(state)
    }
    func perform(kind: WidgetKind, operation: @escaping () throws -> Void, completion: @escaping (String?) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let generation, let slot = slots.first(where: { $0.provider.kinds.contains(kind) }), slot.accepts(generation) else {
            completion("Enable this widget before using its controls."); return
        }
        slot.queue.async {
            var message: String?
            if slot.accepts(generation) { do { try operation() } catch { message = error.localizedDescription } }
            else { message = "The widget configuration changed. Try again." }
            DispatchQueue.main.async { completion(message) }
        }
    }

    /// Explicit settings permission requests may run while a widget is hidden. They still use
    /// its adapter's serial queue, so setup cannot overlap sampling or an ordinary action.
    func performSetup(kind: WidgetKind, operation: @escaping () -> Void, completion: @escaping (String?) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !stopped, let slot = slots.first(where: { $0.provider.kinds.contains(kind) }) else {
            completion("This widget runtime is stopped or unavailable."); return
        }
        slot.queue.async {
            guard slot.allowsSetup else {
                DispatchQueue.main.async { completion("The widget runtime stopped before setup could begin.") }; return
            }
            operation()
            DispatchQueue.main.async { completion(nil) }
        }
    }

    /// Read-only settings discovery uses the provider queue even before live sampling begins.
    /// A stop before execution skips the read; a stop during execution rejects its result.
    func readSetup<Value>(kind: WidgetKind, operation: @escaping () throws -> Value,
                          completion: @escaping (Result<Value, WidgetActionError>) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !stopped, let slot = slots.first(where: { $0.provider.kinds.contains(kind) }) else {
            completion(.failure(WidgetActionError(message: "This widget runtime is stopped or unavailable."))); return
        }
        slot.queue.async {
            let result: Result<Value, WidgetActionError>
            if slot.allowsSetup {
                do { result = .success(try operation()) }
                catch { result = .failure(WidgetActionError(message: error.localizedDescription)) }
            } else { result = .failure(WidgetActionError(message: "The widget runtime stopped before discovery could begin.")) }
            DispatchQueue.main.async {
                guard slot.allowsSetup else {
                    completion(.failure(WidgetActionError(message: "The widget runtime stopped during discovery."))); return
                }
                completion(result)
            }
        }
    }
}
