import Foundation

/// Providers may serve several widgets; sampling occurs only when at least one is enabled.
protocol SystemProviding: AnyObject {
    var kinds: Set<WidgetKind> { get }
    func sample(config: BarConfig, into state: inout SystemState)
}
final class SystemMonitor {
    private let providers: [SystemProviding]
    init(providers: [SystemProviding] = [BatteryProvider(), MetricsProvider(), VPNProvider(), MediaProvider(), WeatherProvider(), AudioProvider(), CalendarProvider(), AgentStatusProvider()]) {
        self.providers = providers
    }
    func sample(config: BarConfig) -> SystemState {
        var state = SystemState()
        let enabled = Set(config.rightWidgets)
        for provider in providers where !provider.kinds.isDisjoint(with: enabled) {
            provider.sample(config: config, into: &state)
        }
        return state
    }
}
