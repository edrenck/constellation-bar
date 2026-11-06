import AppKit

/// Owns System navigation and sorting; the shell supplies chrome and refreshes.
final class SystemPanelContent {
    private enum Tab: Int, CaseIterable {
        case cpu, memory, network, thermal
        var title: String { ["CPU", "MEMORY", "NETWORK", "THERMAL"][rawValue] }
    }
    private enum HistoryRange: Int, CaseIterable {
        case minute, fiveMinutes, hour
        var title: String { ["1m", "5m", "1h"][rawValue] }
        var seconds: Double { [60, 300, 3600][rawValue] }
    }
    private enum ProcessSort {
        case descending, ascending
        var title: String { self == .ascending ? "CPU ↑" : "CPU ↓" }
        var accessibleValue: String { self == .ascending ? "Ascending" : "Descending" }
        mutating func toggle() { self = self == .ascending ? .descending : .ascending }
    }

    private weak var panel: MiniAppPanel?
    private var tab: Tab
    private var historyRange = HistoryRange.fiveMinutes
    private var processSort = ProcessSort.descending

    init(panel: MiniAppPanel) {
        self.panel = panel
        tab = panel.kind == .memory ? .memory : .cpu
    }

    func build() {
        guard let panel else { return }
        let width = panel.bodyWidth
        panel.add(panel.choices(Tab.allCases.map(\.title), selected: tab.rawValue, width: width) { [weak self] index in
            guard let self, let tab = Tab(rawValue: index) else { return }
            self.tab = tab
            self.panel?.rebuild()
        })
        panel.rule()
        if tab == .thermal {
            buildThermal(in: panel)
            return
        }

        let metric = panel.text("", size: 38, width: width-160)
        metric.textColor = panel.config.theme.textAccent(panel.config.theme.blue)
        let ranges = panel.choices(HistoryRange.allCases.map(\.title), selected: historyRange.rawValue, width: 150) { [weak self] index in
            guard let self, let range = HistoryRange(rawValue: index) else { return }
            self.historyRange = range
            self.panel?.rebuild()
        }
        panel.add(panel.row([metric,ranges]), width: width)
        let detail = panel.label("", size: 12, muted: true)
        let graph = MetricPlot()
        graph.theme = panel.config.theme
        graph.seconds = historyRange.seconds
        graph.percentage = tab != .network
        graph.metric = tab == .cpu ? .cpu : tab == .memory ? .memory : .download
        panel.add(graph, width: width, height: 122)
        panel.rule()
        buildTableHeading(in: panel)

        let processFeedback = panel.label("", size: 11, muted: true)
        var cells: [(NSTextField, NSTextField)] = []
        for _ in 0..<3 {
            let name = panel.text("", size: 12, width: width-100)
            let value = panel.text("", size: 12, width: 90)
            value.alignment = .right
            panel.add(panel.row([name,value]), width: width, height: 22)
            cells.append((name,value))
            panel.rule()
        }
        let thermal = panel.text("", size: 10, muted: true, width: width-170)
        let open = panel.button("Open Activity Monitor", treatment: .plain) { [weak self] in
            self?.panel?.openApp("com.apple.ActivityMonitor")
        }
        open.horizontalPadding = 2
        open.font = panel.config.appearance.font(size: 11)
        open.widthAnchor.constraint(equalToConstant: 160).isActive = true
        open.heightAnchor.constraint(equalToConstant: 26).isActive = true
        panel.add(panel.row([thermal,open]), width: width)

        panel.refreshers.append { [weak self, weak metric, weak detail, weak graph, weak thermal, weak processFeedback] in
            guard let self, let panel = self.panel else { return }
            let state = panel.state
            let history = panel.history
            let start = Date(timeIntervalSinceNow: -self.historyRange.seconds)
            processFeedback?.isHidden = self.tab != .cpu || state.topProcessesStatus.isAvailable
            processFeedback?.stringValue = state.topProcessesStatus.description(for: "Process list")
            switch self.tab {
            case .cpu:
                graph?.readingStatus = state.cpu.status
                metric?.stringValue = state.cpu.valueText
                detail?.stringValue = state.cpu.statusDescription
                let dates = history.cpuDates.isEmpty ? history.dates : history.cpuDates
                let count = dates.filter { $0 >= start }.count
                graph?.values = Array(history.cpu.suffix(count))
                graph?.dates = Array(dates.suffix(count))
                let processes = state.topProcesses.sorted {
                    self.processSort == .ascending ? $0.cpu < $1.cpu : $0.cpu > $1.cpu
                }
                for (index,cell) in cells.enumerated() {
                    cell.0.stringValue = processes.indices.contains(index) ? processes[index].name : "—"
                    cell.1.stringValue = processes.indices.contains(index) ? String(format: "%.1f%%",processes[index].cpu) : ""
                }
            case .memory:
                graph?.readingStatus = state.memory.status
                let valid = state.memory.status.isAvailable
                metric?.stringValue = valid ? ByteFormatter.bytes(state.memory.usedBytes) : "—"
                detail?.stringValue = valid ? "of \(ByteFormatter.bytes(state.memory.totalBytes)) memory" : state.memory.status.description(for: "Memory")
                let dates = history.memoryDates.isEmpty ? history.dates : history.memoryDates
                let count = dates.filter { $0 >= start }.count
                graph?.values = Array(history.memory.suffix(count))
                graph?.dates = Array(dates.suffix(count))
                let breakdown = [("Active",state.memory.activeBytes),("Wired",state.memory.wiredBytes),("Compressed",state.memory.compressedBytes)]
                for (index,cell) in cells.enumerated() {
                    cell.0.stringValue = breakdown[index].0
                    cell.1.stringValue = valid ? ByteFormatter.bytes(breakdown[index].1) : "—"
                }
            case .network:
                graph?.readingStatus = state.network.status
                let valid = state.network.status.isAvailable
                metric?.stringValue = valid ? ByteFormatter.compactSpeed(state.network.downloadBytesPerSecond) : "—"
                detail?.stringValue = valid ? "Download · history scales to peak" : state.network.status.description(for: "Network")
                let dates = history.networkDates.isEmpty ? history.dates : history.networkDates
                let count = dates.filter { $0 >= start }.count
                graph?.values = Array(history.network.suffix(count))
                graph?.dates = Array(dates.suffix(count))
                let values = [("Download",valid ? ByteFormatter.speed(state.network.downloadBytesPerSecond) : "—"),
                              ("Upload",valid ? ByteFormatter.speed(state.network.uploadBytesPerSecond) : "—"),
                              ("History","\(count) samples")]
                for (index,cell) in cells.enumerated() {
                    cell.0.stringValue = values[index].0
                    cell.1.stringValue = values[index].1
                }
            case .thermal: break
            }
            thermal?.stringValue = "Thermal state · \(state.thermal.label)"
        }
    }

    private func buildTableHeading(in panel: MiniAppPanel) {
        let width = panel.bodyWidth
        let title = tab == .memory ? "MEMORY BREAKDOWN" : tab == .network ? "TRANSFER RATE" : "TOP PROCESSES"
        guard tab == .cpu else {
            panel.label(title, size: 11, muted: true)
            return
        }
        let heading = panel.text(title, size: 11, muted: true, width: width-70)
        let sort = panel.button(processSort.title, treatment: .plain) { [weak self] in
            self?.processSort.toggle()
            self?.panel?.rebuild()
        }
        sort.identifier = NSUserInterfaceItemIdentifier("system.processSort")
        sort.setAccessibilityLabel("Sort processes by CPU")
        sort.setAccessibilityValue(processSort.accessibleValue)
        sort.horizontalPadding = 2
        sort.widthAnchor.constraint(equalToConstant: 60).isActive = true
        sort.heightAnchor.constraint(equalToConstant: 22).isActive = true
        panel.add(panel.row([heading,sort]), width: width)
    }

    private func buildThermal(in panel: MiniAppPanel) {
        let pressure = panel.label(panel.state.thermal.label, size: 32)
        let explanation = panel.label(WidgetCatalog.thermalExplanation(panel.state.thermal), size: 14)
        panel.rule()
        panel.label("Thermal pressure is macOS’s assessment of cooling demand, rather than a temperature reading.", muted: true)
        panel.add(panel.button("Open Activity Monitor") { [weak self] in
            self?.panel?.openApp("com.apple.ActivityMonitor")
        }, width: panel.bodyWidth, height: 30)
        panel.refreshers.append { [weak self, weak pressure, weak explanation] in
            guard let panel = self?.panel else { return }
            pressure?.stringValue = panel.state.thermal.label
            pressure?.textColor = WidgetCatalog.thermalColor(panel.state.thermal, theme: panel.config.theme)
            explanation?.stringValue = WidgetCatalog.thermalExplanation(panel.state.thermal)
        }
    }
}
