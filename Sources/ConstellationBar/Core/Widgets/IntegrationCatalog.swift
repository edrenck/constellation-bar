import Foundation
import AppKit


struct IntegrationDescriptor {
    let id: String
    let title: String
    let category: String
    let detail: String
    var comingLater = false
}

enum IntegrationCatalog {
    static let all: [IntegrationDescriptor] = [
        .init(id: "codex", title: "Codex (Experimental)", category: "Agents", detail: "Local task activity · read-only status"),
        .init(id: "appleMusic", title: "Apple Music", category: "Media", detail: "Local Music app · playback and seeking"),
        .init(id: "browser", title: "Browser media (Experimental)", category: "Media", detail: "Chrome, Edge and Brave · optional companion extension"),
        .init(id: "spotify", title: "Spotify", category: "Media", detail: "Coming later", comingLater: true),
        .init(id: "appleCalendar", title: "Apple Calendar", category: "Calendar", detail: "Calendars synced to this Mac · read-only agenda"),
        .init(id: "googleCalendar", title: "Google Calendar (direct)", category: "Calendar", detail: "Coming later · synced calendars work through Apple Calendar", comingLater: true),
        .init(id: "outlook", title: "Outlook (direct)", category: "Calendar", detail: "Coming later · synced calendars work through Apple Calendar", comingLater: true),
        .init(id: "systemVPN", title: "macOS VPN services", category: "VPN", detail: "Configured network services"),
        .init(id: "surfshark", title: "Surfshark", category: "VPN", detail: "System service status and app shortcut"),
        .init(id: "tailscale", title: "Tailscale", category: "VPN", detail: "CLI status, peers and exit-node details"),
        .init(id: "otherVPN", title: "More VPN integrations", category: "VPN", detail: "Coming later", comingLater: true)
    ]
}
