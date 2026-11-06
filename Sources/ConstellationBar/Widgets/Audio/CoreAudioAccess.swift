import Foundation
import CoreAudio

struct AudioProperty: Hashable {
    var object: UInt32
    var selector: UInt32
    var scope: UInt32 = kAudioObjectPropertyScopeGlobal
    var element: UInt32 = kAudioObjectPropertyElementMain
    var address: AudioObjectPropertyAddress { AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element) }
    var title: String {
        switch selector {
        case kAudioHardwarePropertyDevices: return "audio device list"
        case kAudioHardwarePropertyDefaultOutputDevice: return "default audio output"
        case kAudioHardwarePropertyDefaultInputDevice: return "default audio input"
        case kAudioObjectPropertyName: return "audio device name"
        case kAudioDevicePropertyStreams: return "audio streams"
        case kAudioDevicePropertyVolumeScalar: return "audio volume"
        case kAudioDevicePropertyMute: return "audio mute status"
        case kAudioDevicePropertyTransportType: return "audio transport"
        default: return "audio property"
        }
    }
}

protocol CoreAudioAccessing {
    func size(_ property: AudioProperty) throws -> UInt32
    func data(_ property: AudioProperty) throws -> Data
    func string(_ property: AudioProperty) throws -> String
    func has(_ property: AudioProperty) -> Bool
    func isSettable(_ property: AudioProperty) throws -> Bool
    func write(_ property: AudioProperty, data: Data) throws
}

/// Only this adapter touches Core Audio buffers and ownership. No failed read supplies a fallback.
struct CoreAudioAccess: CoreAudioAccessing {
    func size(_ property: AudioProperty) throws -> UInt32 {
        var address = property.address, count: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(property.object, &address, 0, nil, &count), "Read size of", property)
        guard count <= 1_048_576 else { throw WidgetActionError(message: "The \(property.title) exceeded the supported response size.") }
        return count
    }
    func data(_ property: AudioProperty) throws -> Data {
        let capacity = try size(property)
        guard capacity > 0 else { return Data() }
        var address = property.address, used = capacity, result = Data(count: Int(capacity))
        let status = result.withUnsafeMutableBytes { AudioObjectGetPropertyData(property.object, &address, 0, nil, &used, $0.baseAddress!) }
        try check(status, "Read", property)
        guard used <= capacity else { throw WidgetActionError(message: "The \(property.title) changed size during reading. Retry the sample.") }
        return result.prefix(Int(used))
    }
    func string(_ property: AudioProperty) throws -> String {
        var address = property.address, value: Unmanaged<CFString>?
        var count = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(property.object, &address, 0, nil, &count, &value)
        try check(status, "Read", property)
        guard count == MemoryLayout<CFString>.size, let value else { throw WidgetActionError(message: "The \(property.title) returned invalid text.") }
        // Only a successful, correctly sized reply contains an owned CFObject to consume.
        return value.takeRetainedValue() as String
    }
    func has(_ property: AudioProperty) -> Bool {
        var address = property.address
        return AudioObjectHasProperty(property.object, &address)
    }
    func isSettable(_ property: AudioProperty) throws -> Bool {
        guard has(property) else { return false }
        var address = property.address, result: DarwinBoolean = false
        try check(AudioObjectIsPropertySettable(property.object, &address, &result), "Read control capability for", property)
        return result.boolValue
    }
    func write(_ property: AudioProperty, data: Data) throws {
        guard !data.isEmpty, data.count <= 1_048_576 else { throw WidgetActionError(message: "Invalid audio control value. Refresh before retrying.") }
        var address = property.address
        let status = data.withUnsafeBytes { AudioObjectSetPropertyData(property.object, &address, 0, nil, UInt32(data.count), $0.baseAddress!) }
        try check(status, "Change", property)
    }
    private func check(_ status: OSStatus, _ operation: String, _ property: AudioProperty) throws {
        guard status == noErr else { throw WidgetActionError(message: "\(operation) \(property.title) failed (Core Audio \(status)). Retry or open Sound settings.") }
    }
}
