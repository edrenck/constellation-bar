import Foundation
import AppKit


struct IntegrationDescriptor {
    let id: String
    let title: String
    let widget: WidgetKind
    let detail: String
    var comingLater = false
}

enum IntegrationCatalog {
    static let all: [IntegrationDescriptor] = [
        .init(id: "codex", title: "Codex (Experimental)", widget: .agentStatus, detail: "Local task activity · read-only status"),
        .init(id: "codexSSH", title: "Codex SSH hosts (Experimental)", widget: .agentStatus, detail: "Read-only status from saved Codex SSH connections · requires Codex provider and Python 3 on each host"),
        .init(id: "appleMusic", title: "Apple Music", widget: .nowPlaying, detail: "Music playback and controls · optional Automation permission"),
        .init(id: "nativeMedia", title: "macOS Now Playing", widget: .nowPlaying, detail: "Active system player · playback and track information"),
        .init(id: "appleCalendar", title: "Apple Calendar", widget: .calendar, detail: "Calendars synced to this Mac · read-only agenda"),
        .init(id: "googleCalendar", title: "Google Calendar (direct)", widget: .calendar, detail: "Coming later · synced calendars work through Apple Calendar", comingLater: true),
        .init(id: "outlook", title: "Outlook via macOS Calendar", widget: .calendar, detail: "Microsoft accounts synced through Internet Accounts · native calendar access"),
        .init(id: "systemVPN", title: "macOS VPN services", widget: .vpn, detail: "Configured network services"),
        .init(id: "surfshark", title: "Surfshark", widget: .vpn, detail: "System service status and app shortcut"),
        .init(id: "tailscale", title: "Tailscale", widget: .vpn, detail: "CLI status, peers and exit-node details"),
        .init(id: "otherVPN", title: "More VPN integrations", widget: .vpn, detail: "Coming later", comingLater: true)
    ]
}
