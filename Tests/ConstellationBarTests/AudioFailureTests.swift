import XCTest
import CoreAudio
@testable import ConstellationBar

final class FixtureAudioHardware: CoreAudioAccessing {
    var values: [AudioProperty: Data] = [:]
    var sizes: [AudioProperty: UInt32] = [:]
    var names: [AudioProperty: String] = [:]
    var failures: [AudioProperty: String] = [:]
    var capabilityFailures: Set<AudioProperty> = []
    var writable: Set<AudioProperty> = []
    var writeFailures: Set<AudioProperty> = []
    var writes: [(AudioProperty, Data)] = []
    static let inventory = AudioProperty(object: UInt32(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDevices)
    static let output = AudioProperty(object: UInt32(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDefaultOutputDevice)
    static let input = AudioProperty(object: UInt32(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDefaultInputDevice)
    static func volume(_ element: UInt32 = 0, input: Bool = false) -> AudioProperty { AudioProperty(object: 10, selector: kAudioDevicePropertyVolumeScalar, scope: input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput, element: element) }
    static func mute(input: Bool = false) -> AudioProperty { AudioProperty(object: 10, selector: kAudioDevicePropertyMute, scope: input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput) }
    static func bytes<T>(_ value: T) -> Data { var value = value; return withUnsafeBytes(of: &value) { Data($0) } }
    init() {
        values[Self.inventory] = Self.bytes(UInt32(10)); values[Self.output] = Self.bytes(UInt32(10)); values[Self.input] = Self.bytes(UInt32(0))
        sizes[AudioProperty(object: 10, selector: kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)] = 4
        sizes[AudioProperty(object: 10, selector: kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeInput)] = 0
        names[AudioProperty(object: 10, selector: kAudioObjectPropertyName)] = "Fixture Speakers"
        values[AudioProperty(object: 10, selector: kAudioDevicePropertyTransportType)] = Self.bytes(UInt32(kAudioDeviceTransportTypeBuiltIn))
        values[Self.volume()] = Self.bytes(Float32(0.5)); values[Self.mute()] = Self.bytes(UInt32(0))
        writable = [Self.output, Self.input, Self.volume(), Self.mute()]
    }
    private func check(_ property: AudioProperty) throws {
        if let message = failures[property] { throw WidgetActionError(message: message) }
    }
    func size(_ property: AudioProperty) throws -> UInt32 {
        try check(property)
        if let size = sizes[property] { return size }
        return UInt32(try data(property).count)
    }
    func data(_ property: AudioProperty) throws -> Data {
        try check(property)
        guard let value = values[property] else { throw WidgetActionError(message: "Missing fixture property: \(property.title)") }
        return value
    }
    func string(_ property: AudioProperty) throws -> String { try check(property); return names[property] ?? "Fixture device" }
    func has(_ property: AudioProperty) -> Bool { values[property] != nil || names[property] != nil }
    func isSettable(_ property: AudioProperty) throws -> Bool {
        if capabilityFailures.contains(property) { throw WidgetActionError(message: "Fixture control capability read failed") }
        return writable.contains(property)
    }
    func write(_ property: AudioProperty, data: Data) throws {
        writes.append((property, data))
        if writeFailures.contains(property) { throw WidgetActionError(message: "Fixture hardware rejected the write") }
        values[property] = data
    }
}

final class AudioFailureTests: XCTestCase {
    func testRuntimeRetryRequestsARealSampleAndRejectsHiddenWidgets() {
        let hardware = FixtureAudioHardware(), audio = AudioProvider(hardware: hardware)
        let runtime = WidgetRuntime(services: WidgetServices(audio: audio))
        let initial = expectation(description: "initial sample"), fresh = expectation(description: "retry sample")
        var config = BarConfig.default; config.rightWidgets = [.audio]
        var first = true
        runtime.refresh(config: config, generation: 1) { state in
            if first, state.audio.output?.volume == 0.5 { first = false; initial.fulfill() }
            if state.audio.output?.volume == 0.75 { fresh.fulfill() }
        }
        wait(for: [initial], timeout: 2)
        hardware.values[FixtureAudioHardware.volume()] = FixtureAudioHardware.bytes(Float32(0.75))
        runtime.perform(.refreshAudio, config: config) { XCTAssertNil($0) }
        wait(for: [fresh], timeout: 2)
        config.rightWidgets = []
        runtime.refresh(config: config, generation: 2) { _ in }
        runtime.perform(.refreshAudio, config: config) { XCTAssertNotNil($0) }
        runtime.stop()
    }
    func testInventoryFailureEmptySuccessAndDefaultReadFailureStayDistinct() {
        let hardware = FixtureAudioHardware(), provider = AudioProvider(hardware: hardware)
        hardware.failures[FixtureAudioHardware.inventory] = "Read audio device list failed (Core Audio -50)"
        let failed = provider.snapshot()
        XCTAssertFalse(failed.status.isAvailable); XCTAssertTrue(failed.devices.isEmpty)
        XCTAssertEqual(WidgetCatalog.module(for: .audio).presentation(audioState(failed), .default, WidgetHistory()).text, "Audio unavailable")
        hardware.failures = [:]; hardware.values[FixtureAudioHardware.inventory] = Data(); hardware.values[FixtureAudioHardware.output] = FixtureAudioHardware.bytes(UInt32(0))
        let empty = provider.snapshot()
        XCTAssertTrue(empty.status.isAvailable); XCTAssertTrue(empty.devices.isEmpty); XCTAssertTrue(empty.allIssues.isEmpty)
        XCTAssertEqual(WidgetCatalog.module(for: .audio).presentation(audioState(empty), .default, WidgetHistory()).text, "No output")
        hardware.failures[FixtureAudioHardware.output] = "Default output read failed"
        let unknown = provider.snapshot()
        XCTAssertEqual(unknown.outputFailure, "Default output read failed")
        XCTAssertEqual(WidgetCatalog.module(for: .audio).presentation(audioState(unknown), .default, WidgetHistory()).text, "Audio output unavailable")
    }
    func testPartialPropertyFailuresNeverBecomeZeroVolumeOrUnmuted() {
        let hardware = FixtureAudioHardware(), provider = AudioProvider(hardware: hardware)
        hardware.failures[FixtureAudioHardware.volume()] = "Volume read failed"
        hardware.failures[FixtureAudioHardware.mute()] = "Mute read failed"
        let partial = provider.snapshot(), device = partial.output
        XCTAssertTrue(partial.status.isAvailable); XCTAssertNotNil(device)
        XCTAssertNil(device?.volume); XCTAssertNil(device?.muted)
        XCTAssertEqual(device?.canSetVolume, false); XCTAssertEqual(device?.canMute, false)
        XCTAssertTrue(partial.allIssues.contains("Volume read failed"))
        hardware.failures = [:]
        let recovered = provider.snapshot().output
        XCTAssertEqual(recovered?.volume, 0.5); XCTAssertEqual(recovered?.muted, false)
        XCTAssertEqual(recovered?.canSetVolume, true); XCTAssertEqual(recovered?.canMute, true)
    }
    func testInvalidPropertyBuffersAndVolumesAreUnavailable() {
        for bytes in [Data([1]), FixtureAudioHardware.bytes(Float32.nan), FixtureAudioHardware.bytes(Float32(-0.1)), FixtureAudioHardware.bytes(Float32(1.1))] {
            let hardware = FixtureAudioHardware(); hardware.values[FixtureAudioHardware.volume()] = bytes
            let output = AudioProvider(hardware: hardware).snapshot().output
            XCTAssertNil(output?.volume); XCTAssertEqual(output?.canSetVolume, false); XCTAssertFalse(output?.issues.isEmpty ?? true)
        }
        let hardware = FixtureAudioHardware(); hardware.values[FixtureAudioHardware.inventory] = Data([1])
        XCTAssertFalse(AudioProvider(hardware: hardware).snapshot().status.isAvailable)
    }
    func testWritesRejectDisconnectedUnknownAndReadOnlyControls() {
        let hardware = FixtureAudioHardware(), provider = AudioProvider(hardware: hardware)
        XCTAssertThrowsError(try provider.volume(10, input: false, value: .nan))
        hardware.capabilityFailures.insert(FixtureAudioHardware.volume())
        XCTAssertThrowsError(try provider.volume(10, input: false, value: 0.8))
        hardware.writable.remove(FixtureAudioHardware.mute())
        XCTAssertThrowsError(try provider.mute(10, input: false, muted: true))
        hardware.values[FixtureAudioHardware.inventory] = Data()
        XCTAssertThrowsError(try provider.select(10, input: false))
        XCTAssertTrue(hardware.writes.isEmpty)
    }
    func testPartialStereoWriteReportsWhatMayHaveChanged() throws {
        let hardware = FixtureAudioHardware(), provider = AudioProvider(hardware: hardware)
        hardware.values[FixtureAudioHardware.volume()] = nil
        for element: UInt32 in [1,2] { hardware.values[FixtureAudioHardware.volume(element)] = FixtureAudioHardware.bytes(Float32(0.5)); hardware.writable.insert(FixtureAudioHardware.volume(element)) }
        hardware.writeFailures.insert(FixtureAudioHardware.volume(2))
        XCTAssertThrowsError(try provider.volume(10, input: false, value: 0.8)) { XCTAssertTrue($0.localizedDescription.contains("Some volume channels may already have changed")) }
        XCTAssertEqual(hardware.writes.count, 2)
        XCTAssertEqual(try XCTUnwrap(provider.snapshot().output?.volume), 0.65, accuracy: 0.001)
    }
    func testInputCommandsDoNotWriteOutputProperties() throws {
        let hardware = FixtureAudioHardware(), provider = AudioProvider(hardware: hardware)
        hardware.sizes[AudioProperty(object: 10, selector: kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeInput)] = 4
        hardware.values[FixtureAudioHardware.input] = FixtureAudioHardware.bytes(UInt32(10))
        hardware.values[FixtureAudioHardware.volume(input: true)] = FixtureAudioHardware.bytes(Float32(0.2)); hardware.values[FixtureAudioHardware.mute(input: true)] = FixtureAudioHardware.bytes(UInt32(0))
        hardware.writable.insert(FixtureAudioHardware.volume(input: true)); hardware.writable.insert(FixtureAudioHardware.mute(input: true))
        try provider.volume(10, input: true, value: 0.7); try provider.mute(10, input: true, muted: true)
        XCTAssertTrue(hardware.writes.allSatisfy { $0.0.scope == kAudioDevicePropertyScopeInput })
        XCTAssertEqual(provider.snapshot().output?.volume, 0.5)
    }
    func testRuntimeSamplesAndCommandsTheSameInjectedHardware() {
        let hardware = FixtureAudioHardware(), audio = AudioProvider(hardware: hardware)
        let runtime = WidgetRuntime(services: WidgetServices(audio: audio))
        let sampled = expectation(description: "sampled"), completed = expectation(description: "volume complete")
        var config = BarConfig.default; config.rightWidgets = [.audio]
        var didSample = false
        runtime.refresh(config: config, generation: 1) { state in if state.audio.output?.volume == 0.5, !didSample { didSample = true; sampled.fulfill() } }
        wait(for: [sampled], timeout: 2)
        runtime.perform(.audioVolume(10, input: false, value: 0.6), config: config) { error in XCTAssertNil(error); completed.fulfill() }
        wait(for: [completed], timeout: 2)
        XCTAssertEqual(hardware.writes.count, 1)
        XCTAssertEqual(audio.snapshot().output?.volume ?? 0, 0.6, accuracy: 0.001)
        runtime.stop()
    }
    func testNativeCoreAudioReadsPreserveErrorStatusForAnInvalidObject() {
        XCTAssertThrowsError(try CoreAudioAccess().write(AudioProperty(object: kAudioObjectUnknown, selector: kAudioDevicePropertyVolumeScalar), data: Data()))
        XCTAssertThrowsError(try CoreAudioAccess().data(AudioProperty(object: kAudioObjectUnknown, selector: kAudioHardwarePropertyDevices))) {
            XCTAssertTrue($0.localizedDescription.contains("Core Audio")); XCTAssertTrue($0.localizedDescription.contains("audio device list"))
        }
        XCTAssertThrowsError(try CoreAudioAccess().string(AudioProperty(object: kAudioObjectUnknown, selector: kAudioObjectPropertyName))) {
            XCTAssertTrue($0.localizedDescription.contains("Core Audio")); XCTAssertTrue($0.localizedDescription.contains("audio device name"))
        }
    }
    private func audioState(_ audio: AudioState) -> SystemState { var state = SystemState(); state.audio = audio; return state }
}
