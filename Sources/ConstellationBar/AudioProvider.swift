import AppKit
import CoreAudio

/// Device identity is best-effort: renamed devices without a model identifier use a generic icon.
enum AudioDeviceIcon {
    static func symbol(name: String, isInput: Bool, transport: UInt32 = 0) -> String {
        if isInput { return "mic" }
        let name = name.lowercased()
        if name.contains("airpods max") { return "airpodsmax" }
        if name.contains("airpods pro") { return "airpodspro" }
        if name.contains("airpods") { return "airpods" }
        if name.contains("headphone") || name.contains("headset") || name.contains("buds") || transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE { return "headphones" }
        if name.contains("display") || transport == kAudioDeviceTransportTypeHDMI || transport == kAudioDeviceTransportTypeDisplayPort { return "display" }
        return "speaker.wave.2"
    }
}
final class AudioProvider: SystemProviding {
    let kinds: Set<WidgetKind> = [.audio, .nowPlaying]
    func sample(config: BarConfig, into state: inout SystemState) { state.audio = snapshot() }
    func snapshot() -> AudioState {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return AudioState() }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return AudioState() }
        var devices: [AudioDeviceState] = []
        for id in ids {
            for input in [false, true] {
                let scope = input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
                var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: scope, mElement: kAudioObjectPropertyElementMain)
                var count: UInt32 = 0
                guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &count) == noErr, count > 0 else { continue }
                var device = AudioDeviceState(id: id, name: name(id), isInput: input, transport: read(id, kAudioDevicePropertyTransportType, default: UInt32(0)))
                let channels = volumeElements(id, scope: scope)
                let values: [Float32] = channels.map { read(id, kAudioDevicePropertyVolumeScalar, scope: scope, element: $0, default: Float32(0)) }
                if !values.isEmpty { device.volume = Double(values.reduce(0, +) / Float(values.count)) }
                device.canSetVolume = !channels.isEmpty && channels.allSatisfy { settable(id, kAudioDevicePropertyVolumeScalar, scope: scope, element: $0) }
                var mute = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: scope, mElement: 0)
                if AudioObjectHasProperty(id, &mute) { device.muted = read(id, kAudioDevicePropertyMute, scope: scope, default: UInt32(0)) != 0 }
                device.canMute = settable(id, kAudioDevicePropertyMute, scope: scope)
                devices.append(device)
            }
        }
        return AudioState(devices: devices, outputID: read(system, kAudioHardwarePropertyDefaultOutputDevice, default: UInt32(0)), inputID: read(system, kAudioHardwarePropertyDefaultInputDevice, default: UInt32(0)))
    }
    private func volumeElements(_ id: AudioObjectID, scope: AudioObjectPropertyScope) -> [UInt32] {
        // Prefer master volume. Stereo channel fallback covers common wired devices.
        for elements: [UInt32] in [[0], [1, 2]] {
            if elements.allSatisfy({ element in
                var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: element)
                return AudioObjectHasProperty(id, &address)
            }) { return elements }
        }
        return []
    }
    func select(_ id: UInt32, input: Bool) throws {
        guard snapshot().devices.contains(where: { $0.id == id && $0.isInput == input }) else { throw WidgetActionError(message: "That audio device is no longer connected.") }
        try write(AudioObjectID(kAudioObjectSystemObject), input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice, value: id)
    }
    func volume(_ id: UInt32, input: Bool, value: Double) throws {
        guard value.isFinite else { return }
        let scope = input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
        let elements = volumeElements(id, scope: scope)
        guard !elements.isEmpty else { throw WidgetActionError(message: "Use this device’s hardware volume controls.") }
        for element in elements { try write(id, kAudioDevicePropertyVolumeScalar, scope: scope, element: element, value: Float32(min(1, max(0, value)))) }
    }
    func mute(_ id: UInt32, input: Bool, muted: Bool) throws {
        try write(id, kAudioDevicePropertyMute, scope: input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput, value: UInt32(muted ? 1 : 0))
    }
    private func name(_ id: AudioObjectID) -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return "Audio device" }
        return value?.takeRetainedValue() as String? ?? "Audio device"
    }
    private func read<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: UInt32 = 0, default fallback: T) -> T {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        var value = fallback, size = UInt32(MemoryLayout<T>.size)
        let result = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0) }
        guard result == noErr else { return fallback }
        return value
    }
    private func settable(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, element: UInt32 = 0) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        var result: DarwinBoolean = false
        return AudioObjectIsPropertySettable(id, &address, &result) == noErr && result.boolValue
    }
    private func write<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: UInt32 = 0, value: T) throws {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        var value = value
        let result = withUnsafePointer(to: &value) { AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<T>.size), $0) }
        guard result == noErr else { throw WidgetActionError(message: "The audio device did not accept the change. It may have disconnected or require hardware controls.") }
    }
}
