import Foundation
import AppKit


struct AudioDeviceState: Equatable {
    var id: UInt32
    var name: String
    var isInput: Bool
    var transport: UInt32 = 0
    var volume: Double? = nil
    var muted: Bool? = nil
    var canSetVolume = false
    var canMute = false
    var issues: [String] = []
    var symbol: String { AudioDeviceIcon.symbol(name: name, isInput: isInput, transport: transport) }
}

struct AudioState: Equatable {
    var devices: [AudioDeviceState] = []
    var outputID: UInt32 = 0
    var inputID: UInt32 = 0
    var status: ReadingStatus = .available
    var outputFailure: String?
    var inputFailure: String?
    var issues: [String] = []
    var output: AudioDeviceState? { devices.first { !$0.isInput && $0.id == outputID } }
    var allIssues: [String] { issues + devices.flatMap(\.issues) }
}
