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
    }
    private let slots: [Slot]
    private var config = BarConfig.default
    private var generation: Int?
    private var update: ((SystemState) -> Void)?
    init(providers: [SystemProviding] = [BatteryProvider(), MetricsProvider(), VPNProvider(), MediaProvider(), WeatherProvider(), WidgetServices.shared.audio, CalendarProvider(), AgentStatusProvider(), WidgetServices.shared.timer, WidgetServices.shared.keepAwake, WidgetServices.shared.reminders, WidgetServices.shared.keyboard]) {
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
    private func deactivate(_ slot: Slot) {
        slot.queue.async { if slot.isDisabled { slot.provider.deactivate() } }
    }
    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        generation = nil; update = nil
        for slot in slots {
            slot.setRevision(nil); slot.pending = false; slot.snapshot = nil
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
}
