import AppKit

/// Task details use the same scrollable panel for hovering and pinning.
extension MiniAppPanel {
    func buildAgents() {
        let agents = state.agents
        let summary: String
        if agents.providers.isEmpty {
            summary = "Monitoring disabled"
        } else if !agents.isComplete {
            summary = agents.activeCount > 0 ? "\(agents.activeCount) active · status incomplete" : "Status unavailable or incomplete"
        } else {
            summary = agents.activeCount == 0 ? "No tasks running" : "\(agents.activeCount) active \(agents.activeCount == 1 ? "task" : "tasks")"
        }
        let title = label(summary, size: 22)
        title.textColor = agents.activeCount > 0 ? config.theme.green : config.theme.foreground
        if agents.providers.isEmpty {
            label("Enable an agent provider in Customize Bar → Connections.", muted: true)
        } else {
            label("Active includes working and waiting for input or approval.", size: 11, muted: true)
        }
        for provider in agents.providers {
            rule()
            let idle = provider.available ? " · \(provider.idleCount) idle" : " · Unavailable"
            label(provider.name + idle, size: 13)
            guard provider.available else {
                label(provider.message, size: 12, muted: true)
                continue
            }
            if provider.tasks.isEmpty {
                label("No open local tasks", muted: true)
            }
            for task in provider.sortedTasks {
                let badgeWidth: CGFloat = 64
                let detailsWidth = bodyWidth - badgeWidth - 12
                let details = column(width: detailsWidth, spacing: 3)
                let taskTitle = text(task.displayTitle, size: 12, width: detailsWidth, weight: .medium)
                taskTitle.maximumNumberOfLines = 2
                taskTitle.lineBreakMode = .byTruncatingTail
                taskTitle.toolTip = task.displayTitle
                details.addArrangedSubview(taskTitle)
                details.addArrangedSubview(text(task.project.isEmpty ? "No project information" : task.project, size: 11, muted: true, width: detailsWidth))
                let activity = text(task.activityLabel, size: 11, width: badgeWidth)
                activity.alignment = .right
                activity.textColor = task.activity == .active ? config.theme.green : task.activity == .unknown ? config.theme.orange : config.theme.muted
                activity.toolTip = task.activity == .active ? "Working or waiting for input or approval" : nil
                add(row([details, activity], spacing: 12), width: bodyWidth)
            }
        }
        if !agents.providers.isEmpty {
            rule()
            label("Saved tasks on this Mac only. Remote, cloud and temporary internal workers are excluded.", size: 10, muted: true)
        }
        refreshers.append { [weak self] in
            guard let self else { return }
            if let date = self.state.agents.providers.compactMap(\.sampledAt).min() {
                self.status.stringValue = "Checked " + DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .medium)
            } else {
                self.status.stringValue = "Not sampled yet"
            }
        }
    }
}
