import Foundation
import IOKit.pwr_mgt

struct KeepAwakeState: Equatable {
    var active = false
    var displayAwake = false
    var remaining: TimeInterval = 0
}
protocol AwakeAssertionDriving {
    func create(display: Bool, seconds: TimeInterval) throws -> UInt32
    func release(_ id: UInt32)
}
struct SystemAwakeAssertionDriver: AwakeAssertionDriving {
    func create(display: Bool, seconds: TimeInterval) throws -> UInt32 {
        var id: IOPMAssertionID = 0
        let type = display ? kIOPMAssertionTypePreventUserIdleDisplaySleep : kIOPMAssertionTypePreventUserIdleSystemSleep
        let result = IOPMAssertionCreateWithDescription(type as CFString, "ConstellationBar Keep Awake" as CFString, "User requested a bounded awake session" as CFString, nil, nil, seconds, kIOPMAssertionTimeoutActionRelease as CFString, &id)
        guard result == kIOReturnSuccess else { throw WidgetActionError(message: "macOS could not create an awake session (\(result)).") }
        return id
    }
    func release(_ id: UInt32) { IOPMAssertionRelease(id) }
}
final class KeepAwakeProvider: SystemProviding {
    let kinds: Set<WidgetKind> = [.keepAwake]
    private let driver: AwakeAssertionDriving
    private let now: () -> TimeInterval
    private var assertion: UInt32?
    private var deadline: TimeInterval = 0
    private var display = false
    init(driver: AwakeAssertionDriving = SystemAwakeAssertionDriver(), now: @escaping () -> TimeInterval = DailyClock.now) { self.driver = driver; self.now = now }
    deinit { stop() }
    func start(seconds: TimeInterval, display: Bool) throws {
        guard seconds.isFinite, seconds >= 60, seconds <= 86400 else { throw WidgetActionError(message: "Choose an awake session between 1 minute and 24 hours.") }
        // Create before replacing so a failed request preserves the existing session.
        let replacement = try driver.create(display: display, seconds: seconds)
        stop(); assertion = replacement; deadline = now() + seconds; self.display = display
    }
    func stop() { if let assertion { driver.release(assertion) }; assertion = nil }
    func snapshot() -> KeepAwakeState {
        if assertion != nil, now() >= deadline { stop() }
        return KeepAwakeState(active: assertion != nil, displayAwake: assertion != nil && display, remaining: assertion == nil ? 0 : max(0, deadline-now()))
    }
    func deactivate() { stop() }
    func sample(config: BarConfig, into state: inout SystemState) { state.keepAwake = snapshot() }
    func merge(snapshot: SystemState, into state: inout SystemState) { state.keepAwake = snapshot.keepAwake }
}
