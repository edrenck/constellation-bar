import AppKit
import CoreAudio

/// Feature-specific content in the shared native widget panel.
extension MiniAppPanel {
    func buildSystem() {
        add(choices(["CPU", "MEMORY", "NETWORK"], selected: selectedTab, width: bodyWidth) { [weak self] index in self?.selectedTab = index; self?.rebuild() }); rule()
        let metric = text("", size: 38, width: bodyWidth-160); metric.textColor = config.theme.blue
        let ranges = choices(["1m", "5m", "1h"], selected: rangeSeconds == 60 ? 0 : rangeSeconds == 300 ? 1 : 2, width: 150) { [weak self] index in self?.rangeSeconds = [60,300,3600][index]; self?.rebuild() }
        add(row([metric, ranges]), width: bodyWidth)
        let detail = label("", size: 12, muted: true)
        let graph = MetricPlot(); graph.theme = config.theme; graph.seconds = rangeSeconds; graph.percentage = selectedTab != 2
        graph.setAccessibilityLabel("Metric history"); add(graph, width: bodyWidth, height: 122); rule()
        let tableHead = text(selectedTab == 1 ? "MEMORY BREAKDOWN" : selectedTab == 2 ? "TRANSFER RATE" : "TOP PROCESSES", size: 11, muted: true, width: bodyWidth-70)
        let sort = button(selectedTab == 1 ? "Bytes" : "CPU ↓", treatment: .plain) { [weak self] in self?.processAscending.toggle(); self?.rebuild() }
        sort.widthAnchor.constraint(equalToConstant: 60).isActive = true; sort.heightAnchor.constraint(equalToConstant: 22).isActive = true
        sort.isEnabled = selectedTab == 0
        add(row([tableHead, sort]), width: bodyWidth)
        var cells: [(NSTextField, NSTextField)] = []
        for _ in 0..<3 {
            let name = text("", size: 12, width: bodyWidth-100), value = text("", size: 12, width: 90); value.alignment = .right
            add(row([name, value]), width: bodyWidth, height: 22); cells.append((name,value)); rule()
        }
        let thermal = text("", size: 10, muted: true, width: bodyWidth-170)
        let open = button("Open Activity Monitor", treatment: .plain) { [weak self] in self?.openApp("com.apple.ActivityMonitor") }; open.horizontalPadding = 2; open.font = config.appearance.font(size: 11); open.widthAnchor.constraint(equalToConstant: 160).isActive = true; open.heightAnchor.constraint(equalToConstant: 26).isActive = true
        add(row([thermal, open]), width: bodyWidth)
        refreshers.append { [weak self, weak metric, weak detail, weak graph, weak thermal] in
            guard let self else { return }
            let h = self.history, start = Date(timeIntervalSinceNow: -self.rangeSeconds)
            let count = h.dates.filter { $0 >= start }.count
            if self.selectedTab == 0 {
                metric?.stringValue = "\(Int(self.state.cpu.usage))%"; detail?.stringValue = "CPU usage"
                graph?.values = Array(h.cpu.suffix(count))
                let processes = self.state.topProcesses.sorted { self.processAscending ? $0.cpu < $1.cpu : $0.cpu > $1.cpu }
                for (index, cell) in cells.enumerated() { cell.0.stringValue = processes.indices.contains(index) ? processes[index].name : "—"; cell.1.stringValue = processes.indices.contains(index) ? String(format:"%.1f%%", processes[index].cpu) : "" }
            } else if self.selectedTab == 1 {
                metric?.stringValue = ByteFormatter.bytes(self.state.memory.usedBytes); detail?.stringValue = "of \(ByteFormatter.bytes(self.state.memory.totalBytes)) memory"
                graph?.values = Array(h.memory.suffix(count))
                let breakdown = [("Active", self.state.memory.activeBytes), ("Wired", self.state.memory.wiredBytes), ("Compressed", self.state.memory.compressedBytes)]
                for (index, cell) in cells.enumerated() { cell.0.stringValue = breakdown[index].0; cell.1.stringValue = ByteFormatter.bytes(breakdown[index].1) }
            } else {
                metric?.stringValue = ByteFormatter.compactSpeed(self.state.network.downloadBytesPerSecond); detail?.stringValue = "Download · history scales to peak"
                graph?.values = Array(h.network.suffix(count))
                let values = [("Download", ByteFormatter.speed(self.state.network.downloadBytesPerSecond)), ("Upload", ByteFormatter.speed(self.state.network.uploadBytesPerSecond)), ("History", "\(count) samples")]
                for (index, cell) in cells.enumerated() { cell.0.stringValue = values[index].0; cell.1.stringValue = values[index].1 }
            }
            graph?.dates = Array(h.dates.suffix(count)); thermal?.stringValue = "Thermal state · \(self.state.thermal.label)"
        }
    }
}
