import Foundation

struct CountdownState: Equatable {
    enum Phase { case ready, running, paused, finished }
    var duration: TimeInterval = 25 * 60
    var remaining: TimeInterval = 25 * 60
    var phase: Phase = .ready
    var running: Bool { phase == .running }
    var finished: Bool { phase == .finished }
    var statusLabel: String {
        switch phase { case .ready: return "Ready"; case .running: return "Running"; case .paused: return "Paused"; case .finished: return "Done" }
    }
}
/// A monotonic clock keeps wall-clock or time-zone changes from altering a countdown.
final class TimerProvider: SystemProviding {
    let kinds: Set<WidgetKind> = [.timer]
    private let now: () -> TimeInterval
    private var value = CountdownState()
    private var deadline: TimeInterval?
    init(now: @escaping () -> TimeInterval = DailyClock.now) { self.now = now }
    func snapshot() -> CountdownState {
        if let deadline {
            value.remaining = max(0, deadline - now())
            if value.remaining == 0 { self.deadline = nil; value.phase = .finished }
        }
        return value
    }
    func start(seconds: TimeInterval) throws {
        guard seconds.isFinite, seconds >= 1, seconds <= 86400 else { throw WidgetActionError(message: "Choose a timer between 1 second and 24 hours.") }
        value = CountdownState(duration: seconds, remaining: seconds, phase: .running)
        deadline = now() + seconds
    }
    func pause() { _ = snapshot(); guard value.running else { return }; deadline = nil; value.phase = .paused }
    func resume() { guard value.phase == .paused, value.remaining > 0 else { return }; deadline = now() + value.remaining; value.phase = .running }
    func reset() { deadline = nil; value.remaining = value.duration; value.phase = .ready }
    func sample(config: BarConfig, into state: inout SystemState) { state.timer = snapshot() }
    func merge(snapshot: SystemState, into state: inout SystemState) { state.timer = snapshot.timer }
}
