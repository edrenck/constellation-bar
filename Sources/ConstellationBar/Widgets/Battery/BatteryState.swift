import Foundation
import AppKit


struct BatteryState: Equatable {
    var percent: Int?
    var isCharging: Bool
    var timeRemainingMinutes: Int? = nil
    var powerSource: String = "Unknown"
}
