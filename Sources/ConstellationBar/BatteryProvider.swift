import AppKit
import IOKit.ps

final class BatteryProvider: SystemProviding {
    let kinds: Set<WidgetKind> = [.battery]
    func sample(config: BarConfig, into state: inout SystemState) { state.battery = sampleBattery() }
    func sampleBattery() -> BatteryState {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
            return BatteryState(percent: nil, isCharging: false)
        }

        let current = description[kIOPSCurrentCapacityKey] as? Int
        let max = description[kIOPSMaxCapacityKey] as? Int
        let percent = current.flatMap { current in max.map { max in max > 0 ? Int(Double(current) / Double(max) * 100.0) : nil } } ?? nil
        let state = description[kIOPSPowerSourceStateKey] as? String
        let isCharging = state == kIOPSACPowerValue || (description[kIOPSIsChargingKey] as? Bool == true)
        let rawMinutes = description[kIOPSTimeToEmptyKey] as? Int
        let minutes = rawMinutes.flatMap { $0 > 0 ? $0 : nil }
        return BatteryState(
            percent: percent,
            isCharging: isCharging,
            timeRemainingMinutes: minutes,
            powerSource: state == kIOPSACPowerValue ? "Power Adapter" : "Battery"
        )
    }

}

extension BatteryProvider {
    static let module = WidgetModule(kind: .battery, priority: 95, presentation: { state, config, _ in
        let battery = state.battery
        let color = battery.isCharging ? config.theme.green : (battery.percent ?? 100) <= 20 ? config.theme.red : config.theme.foreground
        return WidgetPresentation(icon: battery.isCharging ? "battery.100.bolt" : "battery.75", text: battery.percent.map { "\($0)%" } ?? "Unavailable", accent: color)
    }, rows: { state, _ in
        let battery = state.battery
        let estimate = battery.isCharging ? "Power adapter" : battery.timeRemainingMinutes.map { "About \($0 / 60)h \($0 % 60)m" } ?? "Calculating…"
        return [("Charge", battery.percent.map { "\($0)%" } ?? "Unavailable"), ("Estimate", estimate), ("Source", battery.powerSource)]
    })
}
