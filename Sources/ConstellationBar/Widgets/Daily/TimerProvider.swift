import Foundation

struct CountdownState: Equatable {
    var duration: TimeInterval = 25 * 60
    var remaining: TimeInterval = 25 * 60
    var running = false
    var finished = false
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
            if value.remaining == 0 { self.deadline = nil; value.running = false; value.finished = true }
        }
        return value
    }
    func start(seconds: TimeInterval) throws {
        guard seconds.isFinite, seconds >= 1, seconds <= 86400 else { throw WidgetActionError(message: "Choose a timer between 1 second and 24 hours.") }
        value = CountdownState(duration: seconds, remaining: seconds, running: true)
        deadline = now() + seconds
    }
    func pause() { _ = snapshot(); deadline = nil; value.running = false }
    func resume() { guard value.remaining > 0 else { return }; deadline = now() + value.remaining; value.running = true; value.finished = false }
    func reset() { deadline = nil; value.remaining = value.duration; value.running = false; value.finished = false }
    func sample(config: BarConfig, into state: inout SystemState) { state.timer = snapshot() }
    func merge(snapshot: SystemState, into state: inout SystemState) { state.timer = snapshot.timer }
}
