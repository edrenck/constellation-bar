import AppKit
import CoreAudio

/// Feature-specific content in the shared native widget panel.
extension MiniAppPanel {
    func buildAgents() {
        let count = label("", size: 48)
        let caption = label("", size: 13)
        rule()
        if state.agents.providers.isEmpty {
            label("Enable an agent provider in Customize Bar → Connections.", muted: true)
        }
        for provider in state.agents.providers {
            label(provider.name, size: 15)
            let summary = label("", size: 12)
            label(provider.message, size: 11, muted: true)
            refreshers.append { [weak self, weak summary] in
                guard let current = self?.state.agents.providers.first(where: { $0.id == provider.id }) else { return }
                summary?.stringValue = current.available ? "\(current.activeCount) active   ·   \(current.idleCount) idle   ·   \(current.unknownCount) unknown" : "Unavailable"
            }
        }
        rule()
        label("Active includes tasks waiting for your input or approval. Counts cover saved tasks on this Mac. Cloud, remote and temporary internal sessions are excluded.", size: 11, muted: true)
        refreshers.append { [weak self, weak count, weak caption] in
            guard let self else { return }
            count?.stringValue = self.state.agents.isComplete ? "\(self.state.agents.activeCount)" : "—"
            count?.textColor = self.state.agents.activeCount > 0 ? self.config.theme.green : self.config.theme.foreground
            caption?.stringValue = self.state.agents.isComplete ? "Active local tasks" : self.state.agents.providers.isEmpty ? "Monitoring disabled" : "Status unavailable or incomplete"
            if let date = self.state.agents.providers.compactMap(\.sampledAt).min() {
                self.status.stringValue = "Checked " + DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .medium)
            }
        }
    }

}
