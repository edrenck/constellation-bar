import Foundation

extension WidgetZoneLayout {
    mutating func consolidateSystemMetrics() {
        var seen = Set<BarItem>()
        for zone in BarZone.allCases {
            setItems(items(in: zone).map { item in item.widgetKind.map { BarItem.widget($0.canonical) } ?? item }
                .filter { seen.insert($0).inserted }, in: zone)
        }
    }
}
