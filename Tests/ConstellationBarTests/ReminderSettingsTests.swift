import AppKit
import EventKit
import XCTest
@testable import ConstellationBar

final class ReminderSettingsTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError(); try requireGraphicalTests(); _ = NSApplication.shared
    }

    func testPermissionGrantedThroughWidgetRefreshesExistingSettings() {
        let reader = SettingsReminderReader()
        let runtime = WidgetRuntime(services: WidgetServices(reminders: RemindersProvider(reader: reader)))
        var config = BarConfig.default; config.setGlobalWidgets([.reminders])
        let controller = ConfigurationWindowController(config: config, widgets: runtime, onChange: { _ in })
        defer { controller.close(); runtime.stop() }
        runtime.refresh(config: config, generation: 1) { _ in }
        let granted = expectation(description: "widget permission callback")
        runtime.perform(.authorizeReminders, config: config) { error in
            XCTAssertNil(error); granted.fulfill()
        }
        wait(for: [granted], timeout: 2)
        XCTAssertTrue(eventually { controller.reminderListButtons["work"]?.title == "Work fixture" },
                      "An existing settings chooser must see access granted through the widget's runtime")
        XCTAssertEqual(reader.prompts, 1)
        XCTAssertTrue(controller.reminderListChoices.allowButton.isHidden)
    }

    func testReactivationReconcilesInjectedListsWithoutSavingConfiguration() {
        let reader = SettingsReminderReader(); reader.replace(authorized: true, lists: [ReminderList(id: "work", title: "Work fixture")])
        let runtime = WidgetRuntime(services: WidgetServices(reminders: RemindersProvider(reader: reader)))
        var config = BarConfig.default; config.widgetPreferences.reminderListIDs = ["work"]
        var saves = 0
        let controller = ConfigurationWindowController(config: config, widgets: runtime,
            persist: { _ in saves += 1; return .saved(URL(fileURLWithPath: "/dev/null")) }, onChange: { _ in })
        defer { controller.close(); runtime.stop() }
        controller.applicationDidBecomeActive()
        guard eventually({ controller.reminderListButtons["work"]?.title == "Work fixture" }) else {
            XCTFail("Settings list discovery must use its injected reader"); return
        }
        let original = controller.reminderListButtons["work"]
        reader.replace(authorized: true, lists: [ReminderList(id: "work", title: "Renamed fixture"), ReminderList(id: "home", title: "Home fixture")])
        controller.applicationDidBecomeActive()
        XCTAssertTrue(eventually { controller.reminderListButtons["home"] != nil && controller.reminderListButtons["work"]?.title == "Renamed fixture" })
        XCTAssertTrue(controller.reminderListButtons["work"] === original, "Renaming a list must retain its control identity")
        XCTAssertEqual(controller.reminderListButtons["work"]?.state, .on)
        XCTAssertEqual(controller.config.widgetPreferences.reminderListIDs, ["work"])
        XCTAssertEqual(saves, 0, "Provider reconciliation is read-only")
        XCTAssertEqual(reader.prompts, 0)
    }

    func testStoreInvalidationReconcilesVisibleChoicesAndPreservesFocusedIdentity() throws {
        let reader = SettingsReminderReader(); reader.replace(authorized: true, lists: [ReminderList(id: "work", title: "Work fixture")])
        let runtime = WidgetRuntime(services: WidgetServices(reminders: RemindersProvider(reader: reader)))
        let controller = ConfigurationWindowController(config: .default, widgets: runtime, onChange: { _ in })
        defer { controller.close(); runtime.stop() }
        controller.selectWidgetOptions(.widget(.reminders))
        controller.window?.setFrameOrigin(NSPoint(x: -10000, y: -10000)); controller.window?.orderFront(nil)
        XCTAssertTrue(eventually { controller.reminderListButtons["work"] != nil })
        let button = try XCTUnwrap(controller.reminderListButtons["work"])
        XCTAssertTrue(controller.window!.makeFirstResponder(button))
        reader.replace(authorized: true, lists: [ReminderList(id: "home", title: "Home fixture"), ReminderList(id: "work", title: "Renamed fixture")], notify: true)
        XCTAssertTrue(eventually { controller.reminderListButtons["home"] != nil && button.title == "Renamed fixture" })
        XCTAssertTrue(controller.reminderListButtons["work"] === button)
        XCTAssertTrue(controller.window?.firstResponder === button)
        XCTAssertEqual(reader.taskReads, 0)
        XCTAssertEqual(reader.prompts, 0)
    }

    func testUnavailableSelectedListsRemainExplicitUntilUserRemovesThem() throws {
        let reader = SettingsReminderReader(); reader.replace(authorized: true, lists: [ReminderList(id: "work", title: "Work fixture")])
        let runtime = WidgetRuntime(services: WidgetServices(reminders: RemindersProvider(reader: reader)))
        var config = BarConfig.default; config.widgetPreferences.reminderListIDs = ["missing", "work"]
        var saved: [BarConfig] = []
        let controller = ConfigurationWindowController(config: config, widgets: runtime,
            persist: { saved.append($0); return .saved(URL(fileURLWithPath: "/dev/null")) }, onChange: { _ in })
        defer { controller.close(); runtime.stop() }
        XCTAssertTrue(eventually { controller.reminderListButtons["missing"]?.state == .on })
        reader.replace(authorized: true, lists: [ReminderList(id: "home", title: "Home fixture")], notify: true)
        XCTAssertTrue(eventually { controller.reminderListButtons["home"] != nil })
        XCTAssertEqual(controller.reminderListButtons["work"]?.state, .on)
        XCTAssertTrue(controller.reminderListButtons["work"]?.title.hasPrefix("Unavailable selected list") == true)
        XCTAssertEqual(controller.config.widgetPreferences.reminderListIDs, ["missing", "work"])
        XCTAssertTrue(saved.isEmpty, "A deleted or temporarily unavailable list must not silently broaden the filter to all lists")
        try XCTUnwrap(controller.reminderListButtons["missing"]).performClick(nil)
        XCTAssertEqual(controller.config.widgetPreferences.reminderListIDs, ["work"])
        try XCTUnwrap(controller.reminderListButtons["work"]).performClick(nil)
        XCTAssertTrue(controller.config.widgetPreferences.reminderListIDs.isEmpty)
        XCTAssertEqual(saved.count, 2)
    }

    func testRevocationClearsPrivateListNamesWithoutPromptingOrEditingSelection() {
        let reader = SettingsReminderReader(); reader.replace(authorized: true, lists: [ReminderList(id: "work", title: "Private fixture title")])
        let runtime = WidgetRuntime(services: WidgetServices(reminders: RemindersProvider(reader: reader)))
        var config = BarConfig.default; config.widgetPreferences.reminderListIDs = ["work"]
        let controller = ConfigurationWindowController(config: config, widgets: runtime, onChange: { _ in })
        defer { controller.close(); runtime.stop() }
        XCTAssertTrue(eventually { controller.reminderListButtons["work"] != nil })
        reader.replace(authorized: false, lists: [ReminderList(id: "work", title: "Private fixture title")], notify: true)
        XCTAssertTrue(eventually { controller.reminderListButtons.isEmpty && !controller.reminderListChoices.isLoading })
        XCTAssertTrue(controller.reminderListChoices.status.stringValue.contains("Press Allow"))
        XCTAssertFalse(controller.reminderListChoices.allowButton.isHidden)
        XCTAssertEqual(controller.config.widgetPreferences.reminderListIDs, ["work"])
        XCTAssertEqual(reader.prompts, 0)
    }

    func testHiddenWidgetListDiscoveryReadsMetadataOnlyAndUsesIsolatedRuntime() {
        let reader = SettingsReminderReader(); reader.replace(authorized: true, lists: [ReminderList(id: "one", title: "First runtime")])
        let other = SettingsReminderReader(); other.replace(authorized: true, lists: [ReminderList(id: "two", title: "Second runtime")])
        let runtime = WidgetRuntime(services: WidgetServices(reminders: RemindersProvider(reader: reader)))
        let second = WidgetRuntime(services: WidgetServices(reminders: RemindersProvider(reader: other)))
        defer { runtime.stop(); second.stop() }
        let firstDone = expectation(description: "first metadata"), secondDone = expectation(description: "second metadata")
        runtime.readReminderLists { result in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(try? result.get().lists.map(\.title), ["First runtime"]); firstDone.fulfill()
        }
        second.readReminderLists { result in
            XCTAssertEqual(try? result.get().lists.map(\.title), ["Second runtime"]); secondDone.fulfill()
        }
        wait(for: [firstDone, secondDone], timeout: 2)
        XCTAssertTrue(runtime.sampledKinds.isEmpty)
        XCTAssertEqual(reader.taskReads + other.taskReads, 0)
        XCTAssertEqual(reader.prompts + other.prompts, 0)
    }

    func testRevocationDuringDiscoveryCannotPublishPreviouslyReadableNames() {
        let reader = SettingsReminderReader(); reader.replace(authorized: true, lists: [ReminderList(id: "private", title: "Private fixture")])
        reader.beforeListRead = { reader.replace(authorized: false, lists: [ReminderList(id: "private", title: "Private fixture")]) }
        let runtime = WidgetRuntime(services: WidgetServices(reminders: RemindersProvider(reader: reader)))
        defer { runtime.stop() }
        let finished = expectation(description: "revoked snapshot")
        runtime.readReminderLists { result in
            XCTAssertEqual(try? result.get(), ReminderListSnapshot()); finished.fulfill()
        }
        wait(for: [finished], timeout: 1)
        reader.beforeListRead = nil
        XCTAssertEqual(reader.listReads, 1); XCTAssertEqual(reader.prompts, 0)
    }

    func testStoreInvalidationRefreshesActiveWidgetBeforeCacheIntervalElapses() {
        let reader = SettingsReminderReader(); reader.replace(authorized: true, lists: [ReminderList(id: "work", title: "Original fixture")])
        let runtime = WidgetRuntime(services: WidgetServices(reminders: RemindersProvider(reader: reader, now: { Date(timeIntervalSince1970: 100) })))
        defer { runtime.stop() }
        var config = BarConfig.default; config.setGlobalWidgets([.reminders])
        let initial = expectation(description: "original widget data"), changed = expectation(description: "invalidated widget data")
        var sawInitial = false, sawChanged = false
        runtime.refresh(config: config, generation: 1) { state in
            if state.reminders.lists.first?.title == "Original fixture", !sawInitial { sawInitial = true; initial.fulfill() }
            if state.reminders.lists.first?.title == "Renamed fixture", !sawChanged { sawChanged = true; changed.fulfill() }
        }
        wait(for: [initial], timeout: 1)
        reader.replace(authorized: true, lists: [ReminderList(id: "work", title: "Renamed fixture")], notify: true)
        wait(for: [changed], timeout: 1)
        XCTAssertEqual(reader.taskReads, 2)
        XCTAssertEqual(reader.prompts, 0)
    }

    func testQueuedListDiscoveryCannotOverlapSamplingAndIsCancelledByStop() {
        let reader = SettingsReminderReader(); reader.replace(authorized: true, lists: [])
        let entered = expectation(description: "task read entered"), cancelled = expectation(description: "queued metadata rejected")
        let release = DispatchSemaphore(value: 0)
        reader.beforeTaskRead = { entered.fulfill(); _ = release.wait(timeout: .now() + 3) }
        let runtime = WidgetRuntime(services: WidgetServices(reminders: RemindersProvider(reader: reader)))
        defer { runtime.stop(); release.signal() }
        var config = BarConfig.default; config.setGlobalWidgets([.reminders])
        runtime.refresh(config: config, generation: 1) { _ in }
        wait(for: [entered], timeout: 1)
        runtime.readReminderLists { result in
            if case .success = result { XCTFail("Queued discovery must be rejected after stop") }
            cancelled.fulfill()
        }
        runtime.stop(); release.signal()
        wait(for: [cancelled], timeout: 1)
        XCTAssertEqual(reader.listReads, 0)
        XCTAssertEqual(reader.cancellations, 1)
    }

    func testStopRejectsInFlightDiscoveryAndCancelsStoreObservation() {
        let reader = SettingsReminderReader(); reader.replace(authorized: true, lists: [ReminderList(id: "private", title: "Private fixture")])
        let entered = expectation(description: "metadata entered"), cancelled = expectation(description: "in-flight result rejected")
        let release = DispatchSemaphore(value: 0)
        reader.beforeListRead = { entered.fulfill(); _ = release.wait(timeout: .now() + 3) }
        let runtime = WidgetRuntime(services: WidgetServices(reminders: RemindersProvider(reader: reader)))
        defer { runtime.stop(); release.signal() }
        runtime.readReminderLists { result in
            XCTAssertTrue(Thread.isMainThread)
            if case .success = result { XCTFail("A stopped runtime must not publish private discovery results") }
            cancelled.fulfill()
        }
        wait(for: [entered], timeout: 1)
        runtime.stop(); release.signal(); wait(for: [cancelled], timeout: 1)
        XCTAssertEqual(reader.cancellations, 1)
        let rejected = expectation(description: "new discovery rejected")
        runtime.readReminderLists { result in
            if case .success = result { XCTFail("Stopped runtime accepted a new read") }; rejected.fulfill()
        }
        wait(for: [rejected], timeout: 1)
        XCTAssertEqual(reader.listReads, 1)
    }

    func testDiscoveryFailureClearsOldChoicesAndNativeRetryRecovers() {
        let reader = SettingsReminderReader(); reader.replace(authorized: true, lists: [ReminderList(id: "work", title: "Private fixture")])
        let runtime = WidgetRuntime(services: WidgetServices(reminders: RemindersProvider(reader: reader)))
        let controller = ConfigurationWindowController(config: .default, widgets: runtime, onChange: { _ in })
        defer { controller.close(); runtime.stop() }
        XCTAssertTrue(eventually { controller.reminderListButtons["work"] != nil })
        reader.failLists = true; reader.emitChange()
        XCTAssertTrue(eventually { controller.reminderListChoices.status.stringValue.contains("Injected list failure") })
        XCTAssertTrue(controller.reminderListButtons.isEmpty)
        XCTAssertTrue(controller.reminderListChoices.allowButton.isHidden, "A list-service failure is not evidence that permission is missing")
        reader.failLists = false
        controller.reminderListChoices.refreshButton.performClick(nil)
        XCTAssertTrue(eventually { controller.reminderListButtons["work"] != nil })
        XCTAssertFalse(controller.reminderListChoices.status.stringValue.contains("Injected list failure"))
        XCTAssertEqual(reader.taskReads, 0); XCTAssertEqual(reader.prompts, 0)
    }

    func testRefreshBurstCoalescesAndDiscardsSupersededSnapshot() {
        var completions: [(Result<ReminderListSnapshot, WidgetActionError>) -> Void] = []
        let view = ReminderListSettingsView { completions.append($0) }
        view.sync(selectedIDs: ["new"]); view.refresh()
        for _ in 0..<20 { view.refresh() }
        XCTAssertEqual(completions.count, 1)
        completions[0](.success(ReminderListSnapshot(authorized: true, lists: [ReminderList(id: "old", title: "Old snapshot")])))
        XCTAssertEqual(completions.count, 2)
        XCTAssertTrue(view.buttons.isEmpty, "An invalidated snapshot must not flash obsolete choices")
        completions[1](.success(ReminderListSnapshot(authorized: true, lists: [ReminderList(id: "new", title: "Current snapshot")])))
        XCTAssertEqual(view.buttons["new"]?.state, .on)
        XCTAssertNil(view.buttons["old"]); XCTAssertFalse(view.isLoading)
    }

    func testAppleReaderObservesOnlyItsStoreAndCancellationDetaches() {
        let notifications = NotificationCenter(), store = EKEventStore(), otherStore = EKEventStore()
        let reader = AppleRemindersReader(store: store, notifications: notifications)
        var changes = 0
        let cancel = reader.observeListChanges { changes += 1 }
        notifications.post(name: .EKEventStoreChanged, object: otherStore)
        XCTAssertEqual(changes, 0)
        notifications.post(name: .EKEventStoreChanged, object: store)
        XCTAssertEqual(changes, 1)
        cancel()
        notifications.post(name: .EKEventStoreChanged, object: store)
        XCTAssertEqual(changes, 1)
    }

    private func eventually(_ condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: 1)
        while !condition(), Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
        return condition()
    }
}

private final class SettingsReminderReader: RemindersReading {
    private let lock = NSLock()
    private var authorized = false
    private var lists = [ReminderList(id: "work", title: "Work fixture")]
    private var requestCount = 0
    private var listReadCount = 0, taskReadCount = 0, cancellationCount = 0
    private var listFailure = false
    private var changed: (() -> Void)?
    var beforeTaskRead: (() -> Void)?
    var beforeListRead: (() -> Void)?
    var isAuthorized: Bool { lock.lock(); defer { lock.unlock() }; return authorized }
    var prompts: Int { lock.lock(); defer { lock.unlock() }; return requestCount }
    var listReads: Int { lock.lock(); defer { lock.unlock() }; return listReadCount }
    var taskReads: Int { lock.lock(); defer { lock.unlock() }; return taskReadCount }
    var cancellations: Int { lock.lock(); defer { lock.unlock() }; return cancellationCount }
    var failLists: Bool {
        get { lock.lock(); defer { lock.unlock() }; return listFailure }
        set { lock.lock(); listFailure = newValue; lock.unlock() }
    }
    func replace(authorized: Bool, lists: [ReminderList], notify: Bool = false) {
        lock.lock(); self.authorized = authorized; self.lists = lists; lock.unlock()
        if notify { emitChange() }
    }
    func readLists() throws -> [ReminderList] {
        beforeListRead?()
        lock.lock(); defer { lock.unlock() }; listReadCount += 1
        if listFailure { throw WidgetActionError(message: "Injected list failure") }
        return lists
    }
    func observeListChanges(_ changed: @escaping () -> Void) -> () -> Void {
        lock.lock(); self.changed = changed; lock.unlock()
        return { [weak self] in
            guard let self else { return }
            self.lock.lock(); self.changed = nil; self.cancellationCount += 1; self.lock.unlock()
        }
    }
    func emitChange() {
        lock.lock(); let changed = changed; lock.unlock(); changed?()
    }
    func read(listIDs: [String], now: Date) throws -> RemindersState {
        beforeTaskRead?()
        lock.lock(); defer { lock.unlock() }; taskReadCount += 1
        return RemindersState(authorized: authorized, lists: authorized ? lists : [], message: "")
    }
    func requestAccess(completion: @escaping (String?) -> Void) {
        lock.lock(); authorized = true; requestCount += 1; lock.unlock(); completion(nil)
    }
}
