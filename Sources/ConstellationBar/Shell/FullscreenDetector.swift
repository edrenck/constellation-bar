import AppKit
import Darwin

/// Follow the display's active native Space, never window geometry or AX state.
enum FullscreenDetector {
    static func coveredDisplays() -> Set<CGDirectDisplayID> {
        coveredDisplays(NSScreen.screens.map(\.displayID)) { NativeSpaceQuery.shared?.currentSpaceType(on: $0) }
    }

    static func coveredDisplays(_ displays: [CGDirectDisplayID],
                                spaceType: (CGDirectDisplayID) -> Int32?) -> Set<CGDirectDisplayID> {
        // SkyLight type 4 is a native fullscreen Space (including Split View).
        // Unknown state keeps the bar visible rather than guessing from size.
        Set(displays.filter { spaceType($0) == 4 })
    }
}

/// These read-only SkyLight entry points require no Accessibility permission.
/// They are private API: resolve at runtime and fail open if Apple removes them.
private final class NativeSpaceQuery {
    typealias Connection = @convention(c) () -> Int32
    typealias CurrentSpace = @convention(c) (Int32, CFString) -> UInt64
    typealias SpaceType = @convention(c) (Int32, UInt64) -> Int32

    static let shared = NativeSpaceQuery()
    private let handle: UnsafeMutableRawPointer
    private let connection: Connection
    private let currentSpace: CurrentSpace
    private let spaceType: SpaceType

    private init?() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL) else { return nil }
        guard let connection = dlsym(handle, "SLSMainConnectionID"),
              let currentSpace = dlsym(handle, "SLSManagedDisplayGetCurrentSpace"),
              let spaceType = dlsym(handle, "SLSSpaceGetType") else {
            dlclose(handle)
            return nil
        }
        self.handle = handle
        self.connection = unsafeBitCast(connection, to: Connection.self)
        self.currentSpace = unsafeBitCast(currentSpace, to: CurrentSpace.self)
        self.spaceType = unsafeBitCast(spaceType, to: SpaceType.self)
    }

    deinit { dlclose(handle) }

    func currentSpaceType(on display: CGDirectDisplayID) -> Int32? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue(),
              let identifier = CFUUIDCreateString(nil, uuid) else { return nil }
        let cid = connection()
        guard cid != 0 else { return nil }
        let sid = currentSpace(cid, identifier)
        guard sid != 0 else { return nil }
        return spaceType(cid, sid)
    }
}
