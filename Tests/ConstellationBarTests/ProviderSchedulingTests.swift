import XCTest
@testable import ConstellationBar

final class ProviderSchedulingTests: XCTestCase {
    func testFastProviderAndControlsDoNotWaitForStalledPeer() {
        let entered = expectation(description: "slow entered")
        let fast = expectation(description: "battery published")
        let controlled = expectation(description: "control completed")
        let release = DispatchSemaphore(value: 0)
        let slow = SchedulingProvider(kinds: [.weather]) { _, _ in entered.fulfill(); _ = release.wait(timeout: .now() + 3) }
        let battery = SchedulingProvider(kinds: [.battery]) { _, state in state.battery.percent = 73 }
        let monitor = SystemMonitor(providers: [slow, battery])
        var config = BarConfig.default; config.rightWidgets = [.weather, .battery]
        var published = false
        monitor.refresh(config: config, generation: 1) { state in
            if state.battery.percent == 73, !published { published = true; fast.fulfill() }
        }
        wait(for: [entered, fast], timeout: 1)
        monitor.perform(kind: .battery, operation: { battery.recordControl() }) { error in
            XCTAssertNil(error); controlled.fulfill()
        }
        wait(for: [controlled], timeout: 0.5)
        XCTAssertEqual(battery.maximumConcurrentAccess, 1)
        monitor.stop(); release.signal()
    }
    func testControlsStaySerializedWithTheirOwnAdapter() {
        let entered = expectation(description: "sample entered")
        let premature = expectation(description: "control cannot overlap sample"); premature.isInverted = true
        let controlled = expectation(description: "serialized control")
        let release = DispatchSemaphore(value: 0)
        let provider = SchedulingProvider(kinds: [.battery]) { _, _ in
            entered.fulfill(); _ = release.wait(timeout: .now() + 3)
        }
        let monitor = SystemMonitor(providers: [provider])
        var config = BarConfig.default; config.rightWidgets = [.battery]
        monitor.refresh(config: config, generation: 1) { _ in }
        wait(for: [entered], timeout: 1)
        monitor.perform(kind: .battery, operation: {
            provider.recordControl()
            if provider.maximumConcurrentAccess > 1 { premature.fulfill() }
        }) { error in XCTAssertNil(error); controlled.fulfill() }
        wait(for: [premature], timeout: 0.1)
        release.signal(); wait(for: [controlled], timeout: 1)
        XCTAssertEqual(provider.maximumConcurrentAccess, 1)
        monitor.stop()
    }
    func testStaleGenerationAndDisabledProviderCannotPublishOrScheduleMoreWork() {
        let entered = expectation(description: "old entered")
        let newValue = expectation(description: "new configuration published")
        let release = DispatchSemaphore(value: 0)
        let slow = SchedulingProvider(kinds: [.battery]) { config, state in
            if config.height == 48 { entered.fulfill(); _ = release.wait(timeout: .now() + 3) }
            state.battery.percent = Int(config.height)
        }
        let monitor = SystemMonitor(providers: [slow])
        var config = BarConfig.default; config.height = 48; config.rightWidgets = [.battery]
        var seen: [Int] = []
        monitor.refresh(config: config, generation: 1) { if let percent = $0.battery.percent { seen.append(percent) } }
        wait(for: [entered], timeout: 1)
        config.height = 52
        monitor.refresh(config: config, generation: 2) { state in
            if let percent = state.battery.percent { seen.append(percent); if percent == 52 { newValue.fulfill() } }
        }
        release.signal()
        wait(for: [newValue], timeout: 1)
        XCTAssertEqual(seen, [52])
        config.rightWidgets = []
        monitor.refresh(config: config, generation: 3) { XCTAssertNil($0.battery.percent) }
        let denied = expectation(description: "disabled controls rejected")
        monitor.perform(kind: .battery, operation: { XCTFail("disabled operation") }) { error in XCTAssertNotNil(error); denied.fulfill() }
        wait(for: [denied], timeout: 1)
        XCTAssertEqual(slow.calls, 2)
        monitor.stop()
    }
    func testDisablingReleasesOwnedResourcesOnTheProviderQueue() {
        let sampled = expectation(description: "sampled")
        let deactivated = expectation(description: "released")
        let provider = SchedulingProvider(kinds: [.battery]) { _, state in state.battery.percent = 50 }
        provider.onDeactivate = { deactivated.fulfill() }
        let monitor = SystemMonitor(providers: [provider])
        var config = BarConfig.default; config.rightWidgets = [.battery]
        monitor.refresh(config: config, generation: 1) { if $0.battery.percent == 50 { sampled.fulfill() } }
        wait(for: [sampled], timeout: 1)
        config.rightWidgets = []
        monitor.refresh(config: config, generation: 2) { XCTAssertNil($0.battery.percent) }
        wait(for: [deactivated], timeout: 1)
        XCTAssertEqual(provider.maximumConcurrentAccess, 1)
        monitor.stop()
    }
    func testDisablingInFlightProviderDropsPendingResample() {
        let entered = expectation(description: "entered")
        let ended = expectation(description: "ended")
        let release = DispatchSemaphore(value: 0)
        let provider = SchedulingProvider(kinds: [.battery]) { _, state in
            entered.fulfill(); _ = release.wait(timeout: .now() + 3); state.battery.percent = 99; ended.fulfill()
        }
        let monitor = SystemMonitor(providers: [provider])
        var config = BarConfig.default; config.rightWidgets = [.battery]
        monitor.refresh(config: config, generation: 1) { XCTAssertNil($0.battery.percent) }
        wait(for: [entered], timeout: 1)
        monitor.refresh(config: config, generation: 1) { XCTAssertNil($0.battery.percent) }
        config.rightWidgets = []
        monitor.refresh(config: config, generation: 2) { XCTAssertNil($0.battery.percent) }
        release.signal(); wait(for: [ended], timeout: 1)
        monitor.stop(); XCTAssertEqual(provider.calls, 1)
    }
}
private final class SchedulingProvider: SystemProviding {
    let kinds: Set<WidgetKind>
    private let body: (BarConfig, inout SystemState) -> Void
    private let lock = NSLock()
    private var count = 0, active = 0, maximum = 0
    var onDeactivate: (() -> Void)?
    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
    var maximumConcurrentAccess: Int { lock.lock(); defer { lock.unlock() }; return maximum }
    init(kinds: Set<WidgetKind>, body: @escaping (BarConfig, inout SystemState) -> Void) { self.kinds = kinds; self.body = body }
    private func enter() { lock.lock(); active += 1; maximum = max(maximum, active); lock.unlock() }
    private func leave() { lock.lock(); active -= 1; lock.unlock() }
    func sample(config: BarConfig, into state: inout SystemState) {
        enter(); defer { leave() }; lock.lock(); count += 1; lock.unlock(); body(config, &state)
    }
    func deactivate() { enter(); defer { leave() }; onDeactivate?() }
    func recordControl() { enter(); leave() }
}
