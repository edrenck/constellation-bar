import AppKit
import CoreAudio

/// Feature-specific content in the shared native widget panel.
extension MiniAppPanel {
    func buildVPN() {
        let active = state.vpn.connections.filter(\.connected).count
        label("\(active) active connection\(active == 1 ? "" : "s")", size: 13, muted: true)
        if selectedVPN.isEmpty { selectedVPN = state.vpn.connections.first(where: { !$0.peers.isEmpty })?.id ?? state.vpn.connections.first(where: \.connected)?.id ?? "" }
        if state.vpn.connections.isEmpty { label("No VPN services found. Check provider setup in Connections.", muted: true) }
        for connection in state.vpn.connections {
            let expanded = connection.id == selectedVPN
            let card = PanelCard(width: bodyWidth, theme: config.theme, selected: expanded && connection.connected)
            let inner = bodyWidth-24
            let tile = PanelGlyph()
            tile.image = NSImage(systemSymbolName: connection.symbol, accessibilityDescription: connection.serviceName)
            tile.color = config.theme.foreground; tile.tile = config.theme.surfaceStrong
            let appIDs = connection.provider == "surfshark" ? ["com.surfshark.vpnclient.macos.direct", "com.surfshark.vpnclient.macos"] : connection.provider == "tailscale" ? ["io.tailscale.ipn.macsys", "io.tailscale.ipn.macos"] : []
            if let appURL = appIDs.compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }).first {
                tile.image = NSWorkspace.shared.icon(forFile: appURL.path)
                tile.preservesImageColors = true; tile.tile = nil
            }
            tile.setAccessibilityLabel(connection.serviceName)
            tile.widthAnchor.constraint(equalToConstant: 34).isActive = true; tile.heightAnchor.constraint(equalToConstant: 34).isActive = true
            let title = column(width: inner-172, spacing: 4)
            add(text(connection.serviceName, size: 13, width: inner-172, weight: .semibold), to: title)
            var subtitle = connection.provider == "tailscale" ? "Mesh network" : connection.protocolName.isEmpty ? "VPN service" : connection.protocolName
            if state.vpn.connections.filter({ $0.serviceName == connection.serviceName }).count > 1 && !connection.id.isEmpty { subtitle += " · " + connection.id.prefix(6) }
            add(text(subtitle, size: 11, muted: true), to: title)
            let badge = text(connection.connected ? "● Connected" : "● Offline", size: 11, width: 92)
            badge.textColor = connection.connected ? (config.appearance == .cove ? config.theme.blue : config.theme.green) : config.theme.muted
            let expand = iconButton(expanded ? "chevron.up" : "chevron.down", label: expanded ? "Collapse \(connection.serviceName)" : "Expand \(connection.serviceName)", size: 12) { [weak self] in self?.selectedVPN = expanded ? "collapsed" : connection.id; self?.peerQuery = ""; self?.rebuild() }
            expand.widthAnchor.constraint(equalToConstant: 22).isActive = true; expand.heightAnchor.constraint(equalToConstant: 30).isActive = true
            add(row([tile, title, badge, expand], spacing: 8), width: inner, height: 44, to: card.content)
            if expanded {
                rule(width: inner, to: card.content)
                if !connection.profileName.isEmpty { add(text("Profile · " + connection.profileName, size: 12, width: inner), to: card.content) }
                add(text(connection.detail, size: 11, muted: true, width: inner), to: card.content)
                if !connection.peers.isEmpty {
                    add(text("Devices", size: 13, weight: .semibold), to: card.content)
                    let search = NSSearchField(); search.placeholderString = "Find a device"; search.stringValue = peerQuery
                    search.setAccessibilityLabel("Find a VPN device"); search.delegate = self
                    add(search, width: inner, height: 28, to: card.content)
                    let peers = column(width: inner); peerContainer = peers; currentPeers = connection.peers; add(peers, to: card.content); updatePeers()
                }
                let action: WidgetActionButton
                if connection.canToggle { action = button(connection.connected ? "Disconnect" : "Connect") { [weak self] in self?.perform(.vpn(service: connection.id, connected: !connection.connected)) } }
                else { action = button(connection.provider == "tailscale" ? "Open Tailscale" : connection.provider == "surfshark" ? "Open Surfshark" : "VPN settings") { [weak self] in
                    if connection.provider == "tailscale" { self?.openApp("io.tailscale.ipn.macos") }
                    else if connection.provider == "surfshark" { self?.openApp("com.surfshark.vpnclient.macos") }
                    else { self?.openURL("x-apple.systempreferences:com.apple.NetworkExtensionSettingsUI.NESettingsUIExtension") }
                } }
                add(action, width: inner, height: 32, to: card.content)
            }
            add(card)
        }
        label("Routing details depend on the provider.", size: 11, muted: true)
    }
    func controlTextDidChange(_ notification: Notification) {
        guard let search = notification.object as? NSSearchField else { return }; peerQuery = search.stringValue; updatePeers()
    }
    func updatePeers() {
        guard let container = peerContainer else { return }
        container.arrangedSubviews.forEach { container.removeArrangedSubview($0); $0.removeFromSuperview() }
        let matches = currentPeers.filter { peerQuery.isEmpty || $0.localizedCaseInsensitiveContains(peerQuery) }
        for peer in matches {
            let pieces = peer.components(separatedBy: " · ")
            let glyph = PanelGlyph(); glyph.image = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: nil); glyph.color = config.theme.muted
            glyph.widthAnchor.constraint(equalToConstant: 20).isActive = true; glyph.heightAnchor.constraint(equalToConstant: 20).isActive = true
            let name = text(pieces.first ?? peer, size: 12, width: bodyWidth-144)
            let online = pieces.last == "Online"; let status = text(online ? "● Online" : "● Offline", size: 11, width: 70); status.textColor = online ? (config.appearance == .cove ? config.theme.blue : config.theme.green) : config.theme.muted
            add(row([glyph, name, status], spacing: 8), height: 30, to: container)
        }
        if matches.isEmpty { add(text("No matching devices", size: 11, muted: true), to: container) }
        needsLayout = true
    }

}
