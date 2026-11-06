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
    let kinds: Set<WidgetKind> = [.audio]
    private let hardware: CoreAudioAccessing
    init(hardware: CoreAudioAccessing = CoreAudioAccess()) { self.hardware = hardware }
    func sample(config: BarConfig, into state: inout SystemState) { state.audio = snapshot() }
    func snapshot() -> AudioState {
        let system = UInt32(kAudioObjectSystemObject)
        let ids: [UInt32]
        do {
            let bytes = try hardware.data(AudioProperty(object: system, selector: kAudioHardwarePropertyDevices))
            guard bytes.count % 4 == 0, bytes.count/4 <= 4096 else { throw WidgetActionError(message: "The audio device list was incomplete or too large. Retry the sample.") }
            ids = bytes.withUnsafeBytes { buffer in stride(from: 0, to: bytes.count, by: 4).map { buffer.loadUnaligned(fromByteOffset: $0, as: UInt32.self) } }
        } catch { return AudioState(status: .failed(error.localizedDescription)) }
        var result = AudioState()
        do { result.outputID = try scalar(AudioProperty(object: system, selector: kAudioHardwarePropertyDefaultOutputDevice), as: UInt32.self) }
        catch { result.outputFailure = error.localizedDescription; result.issues.append(error.localizedDescription) }
        do { result.inputID = try scalar(AudioProperty(object: system, selector: kAudioHardwarePropertyDefaultInputDevice), as: UInt32.self) }
        catch { result.inputFailure = error.localizedDescription; result.issues.append(error.localizedDescription) }
        for id in Set(ids).sorted() where id != kAudioObjectUnknown {
            for input in [false, true] {
                let scope = input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
                do {
                    let bytes = try hardware.size(AudioProperty(object: id, selector: kAudioDevicePropertyStreams, scope: scope))
                    guard bytes % 4 == 0 else { throw WidgetActionError(message: "The audio stream list was incomplete.") }
                    guard bytes > 0 else { continue }
                } catch { result.issues.append("Device \(id), \(input ? "input" : "output"): \(error.localizedDescription)"); continue }
                var issues: [String] = []
                let name = capture(&issues) { try hardware.string(AudioProperty(object: id, selector: kAudioObjectPropertyName)) } ?? "Audio device \(id)"
                let transport = capture(&issues) { try scalar(AudioProperty(object: id, selector: kAudioDevicePropertyTransportType), as: UInt32.self) } ?? 0
                var device = AudioDeviceState(id: id, name: name, isInput: input, transport: transport)
                let channels = volumeElements(id, scope: scope)
                if !channels.isEmpty {
                    device.volume = capture(&issues) {
                        let values: [Float32] = try channels.map { element in
                            let value = try scalar(AudioProperty(object: id, selector: kAudioDevicePropertyVolumeScalar, scope: scope, element: element), as: Float32.self)
                            guard value.isFinite, (0...1).contains(value) else { throw WidgetActionError(message: "The audio volume reading was invalid. Retry the sample.") }
                            return value
                        }
                        return Double(values.reduce(0,+))/Double(values.count)
                    }
                    device.canSetVolume = device.volume != nil && (capture(&issues) { try channels.allSatisfy { try hardware.isSettable(AudioProperty(object: id, selector: kAudioDevicePropertyVolumeScalar, scope: scope, element: $0)) } } ?? false)
                }
                let mute = AudioProperty(object: id, selector: kAudioDevicePropertyMute, scope: scope)
                if hardware.has(mute) {
                    device.muted = capture(&issues) { try scalar(mute, as: UInt32.self) != 0 }
                    device.canMute = device.muted != nil && (capture(&issues) { try hardware.isSettable(mute) } ?? false)
                }
                device.issues = issues; result.devices.append(device)
            }
        }
        return result
    }
    private func capture<T>(_ issues: inout [String], _ operation: () throws -> T) -> T? {
        do { return try operation() } catch { issues.append(error.localizedDescription); return nil }
    }
    private func scalar<T>(_ property: AudioProperty, as type: T.Type) throws -> T {
        let bytes = try hardware.data(property)
        guard bytes.count == MemoryLayout<T>.size else { throw WidgetActionError(message: "The \(property.title) returned an incomplete value. Retry the sample.") }
        return bytes.withUnsafeBytes { $0.loadUnaligned(as: type) }
    }
    private func volumeElements(_ id: UInt32, scope: UInt32) -> [UInt32] {
        func has(_ element: UInt32) -> Bool { hardware.has(AudioProperty(object: id, selector: kAudioDevicePropertyVolumeScalar, scope: scope, element: element)) }
        if has(0) { return [0] }
        // Without master volume, support mono/stereo controls. Multichannel outputs use hardware.
        guard has(1), !has(3) else { return [] }
        return has(2) ? [1,2] : [1]
    }
    private func device(_ id: UInt32, input: Bool) throws -> AudioDeviceState {
        let state = snapshot()
        guard state.status.isAvailable else { throw WidgetActionError(message: state.status.description(for: "Audio")) }
        guard let device = state.devices.first(where: { $0.id == id && $0.isInput == input }) else { throw WidgetActionError(message: "That audio device could not be verified. It may have disconnected. Retry the sample.") }
        return device
    }
    func select(_ id: UInt32, input: Bool) throws {
        _ = try device(id, input: input)
        try write(AudioProperty(object: UInt32(kAudioObjectSystemObject), selector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice), value: id)
    }
    func volume(_ id: UInt32, input: Bool, value: Double) throws {
        guard value.isFinite else { throw WidgetActionError(message: "Choose a finite audio volume.") }
        let selected = try device(id, input: input)
        guard selected.canSetVolume else { throw WidgetActionError(message: selected.issues.first ?? "Use this device’s hardware volume controls.") }
        let scope = input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
        let elements = volumeElements(id, scope: scope)
        guard !elements.isEmpty else { throw WidgetActionError(message: "The device’s volume controls changed. Refresh before retrying.") }
        var changed = false
        for element in elements {
            do { try write(AudioProperty(object: id, selector: kAudioDevicePropertyVolumeScalar, scope: scope, element: element), value: Float32(min(1,max(0,value)))); changed = true }
            catch { throw WidgetActionError(message: (changed ? "Some volume channels may already have changed. " : "") + error.localizedDescription) }
        }
    }
    func mute(_ id: UInt32, input: Bool, muted: Bool) throws {
        let selected = try device(id, input: input)
        guard selected.canMute else { throw WidgetActionError(message: selected.issues.first ?? "This device does not support software mute.") }
        try write(AudioProperty(object: id, selector: kAudioDevicePropertyMute, scope: input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput), value: UInt32(muted ? 1 : 0))
    }
    private func write<T>(_ property: AudioProperty, value: T) throws {
        var value = value
        try withUnsafeBytes(of: &value) { try hardware.write(property, data: Data($0)) }
    }
}
