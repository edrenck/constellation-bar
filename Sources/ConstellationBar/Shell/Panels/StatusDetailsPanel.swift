import AppKit

/// Battery and Weather use the same full-size shell and controls as System.
extension MiniAppPanel {
    func buildStatusDetails() {
        let weather = kind == .weather
        let value = weather
            ? state.weather.temperature.map { "\(Int($0.rounded()))\(config.weather.unit.symbol)" } ?? "—"
            : state.battery.percent.map { "\($0)%" } ?? "—"
        let subtitle = weather
            ? (config.weather.isConfigured ? config.weather.locationLabel : "Weather is not configured")
            : (state.battery.percent == nil ? "Battery unavailable" : state.battery.isCharging ? "Charging" : state.battery.powerSource)
        let hero = PanelCard(width: bodyWidth, theme: config.theme)
        let inner = bodyWidth - 24
        let glyph = PanelGlyph()
        glyph.image = NSImage(systemSymbolName: weather ? state.weather.symbolName : state.battery.isCharging ? "battery.100.bolt" : "battery.75", accessibilityDescription: nil)
        glyph.color = config.theme.foreground
        add(glyph, width: 48, height: 48, to: hero.content)
        add(text(value, size: 48, width: inner, weight: .medium), to: hero.content)
        add(text(subtitle, size: 14, muted: true, width: inner), to: hero.content)
        add(hero)

        let details = PanelCard(width: bodyWidth, theme: config.theme)
        let rows = WidgetCatalog.module(for: kind).rows(state, config)
        for (index, detail) in rows.enumerated() {
            if index > 0 { rule(width: inner, to: details.content) }
            let title = text(detail.0, size: 12, muted: true, width: 128)
            let value = text(detail.1, size: 13, width: inner - 138, weight: .medium)
            value.alignment = .right
            add(row([title, value]), width: inner, to: details.content)
        }
        add(details)
        if weather {
            label(config.weather.isConfigured ? "Current conditions · Open-Meteo" : "Choose a location in Widgets settings to see current conditions.", size: 11, muted: true)
        }
    }
}
