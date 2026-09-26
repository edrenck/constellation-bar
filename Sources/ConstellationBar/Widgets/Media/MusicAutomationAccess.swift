import AppKit
import Carbon

/// Consent can wait on a human. Keep it off the main and system-sampling queues.
final class MusicAutomationAccess {
    enum State: Equatable {
        case allowed, requiresConsent, requesting, denied
        case unavailable(OSStatus)
    }
    private let lock = NSLock()
    private var attempted = false
    private var requesting = false
    private var lastResponse: State?
    private let authorization: (Bool) -> State
    private let schedule: (@escaping () -> Void) -> Void

    init(authorization: @escaping (Bool) -> State = MusicAutomationAccess.check,
         schedule: @escaping (@escaping () -> Void) -> Void = { work in DispatchQueue.global(qos: .userInitiated).async(execute: work) }) {
        self.authorization = authorization; self.schedule = schedule
    }

    func state(requestIfNeeded: Bool) -> State {
        lock.lock()
        if requesting { lock.unlock(); return .requesting }
        lock.unlock()
        let current = authorization(false)
        lock.lock()
        if current == .allowed { lock.unlock(); return current }
        if requesting { lock.unlock(); return .requesting }
        guard current == .requiresConsent else { lock.unlock(); return current }
        if attempted || !requestIfNeeded {
            let response = lastResponse == .denied ? State.denied : current
            lock.unlock(); return response
        }
        attempted = true; requesting = true
        lock.unlock()
        schedule { [self] in
            let response = authorization(true)
            lock.lock(); lastResponse = response; requesting = false; lock.unlock()
        }
        return .requesting
    }

    static func check(ask: Bool) -> State {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.Music")
        switch AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask) {
        case noErr: return .allowed
        case OSStatus(errAEEventWouldRequireUserConsent): return .requiresConsent
        case OSStatus(errAEEventNotPermitted): return .denied
        case let status: return .unavailable(status)
        }
    }
}
