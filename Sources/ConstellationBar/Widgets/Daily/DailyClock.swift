import Foundation
import Darwin

/// Continuous monotonic time includes sleep and ignores changes to the wall clock.
enum DailyClock {
    private static let secondsPerTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()
    static func now() -> TimeInterval { Double(mach_continuous_time()) * secondsPerTick }
}
