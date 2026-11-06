import AppKit

/// Owns Music selection and content; the shared panel supplies chrome and action routing.
final class MediaPanelContent: NSObject {
    private weak var panel: MiniAppPanel?
    private var selectedSession = ""
    private var mediaTab = 0

    init(panel: MiniAppPanel) { self.panel = panel; super.init() }

    func signature(for state: SystemState) -> String {
        state.mediaSessions.map { "\($0.id)|\($0.playback.title)|\($0.playback.artist)|\($0.album)|\($0.playback.duration)|\($0.artwork?.hashValue ?? 0)|\($0.canSeek)|\($0.canSkip)|\($0.shuffle != nil)|\($0.repeatMode != nil)" }.joined() + state.providerStatuses.description
    }

    func build() {
        guard let panel else { return }
        let state = panel.state, config = panel.config, bodyWidth = panel.bodyWidth
        let compact = panel.compactContent
        let sessions = state.mediaSessions
        if !sessions.contains(where: { $0.id == selectedSession }) { selectedSession = sessions.first(where: { $0.playback.isPlaying })?.id ?? sessions.first?.id ?? "" }
        if sessions.count > 1 {
            let popup = NSPopUpButton(); popup.addItems(withTitles: sessions.map { "\($0.playback.source) · \($0.playback.title.prefix(32))" })
            popup.setAccessibilityLabel("Playback source")
            popup.identifier = NSUserInterfaceItemIdentifier("media.source")
            popup.selectItem(at: sessions.firstIndex(where: { $0.id == selectedSession }) ?? 0)
            popup.target = self; popup.action = #selector(mediaSourceChanged(_:)); panel.add(popup, width: bodyWidth)
        }
        guard let session = sessions.first(where: { $0.id == selectedSession }) else {
            if !compact {
                let glyph = PanelGlyph(); glyph.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil); glyph.color = config.theme.muted; glyph.tile = config.theme.surface
                panel.add(panel.row([NSView(),glyph,NSView()]),width: bodyWidth,height: 80)
                glyph.widthAnchor.constraint(equalToConstant: 80).isActive = true
            }
            panel.label(state.mediaNeedsAttention ? "Music needs attention" : "Nothing playing", size: compact ? 20 : 23)
            func addAccessActions() {
                if config.providerPreferences.includes("appleMusic") {
                    let denied = state.providerStatuses.contains { $0.id == "appleMusic" && $0.message.contains("access was denied") }
                    panel.add(panel.button(denied ? "Open Automation settings…" : "Allow Apple Music access…") { [weak self] in self?.panel?.perform(.authorizeMusic) },width: bodyWidth,height: 34)
                    panel.add(panel.button("Open Music") { [weak self] in self?.panel?.openApp("com.apple.Music") },width: bodyWidth,height: 30)
                }
            }
            if compact { addAccessActions() }
            for provider in state.providerStatuses where ["nativeMedia", "appleMusic"].contains(provider.id) { panel.label(provider.message, muted: true) }
            if !compact { addAccessActions() }
            panel.label("Start playback in any app that appears in macOS Now Playing.", muted: true)
            return
        }
        let art = NSImageView(); art.image = session.artwork.flatMap(NSImage.init(data:)) ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: "Artwork unavailable")
        art.imageScaling = .scaleProportionallyUpOrDown; art.wantsLayer = true; art.layer?.cornerRadius = 9; art.layer?.masksToBounds = true
        let artSize: CGFloat = compact ? 48 : 148
        let gap: CGFloat = compact ? 12 : 18
        let metadataWidth = bodyWidth-artSize-gap
        art.widthAnchor.constraint(equalToConstant: artSize).isActive = true
        art.heightAnchor.constraint(equalToConstant: artSize).isActive = true
        let metadata = panel.column(width: metadataWidth, spacing: compact ? 4 : 8)
        if !compact { panel.add(panel.text("NOW PLAYING", size: 10, muted: true), to: metadata) }
        func metadataLabel(_ value: String, size: CGFloat, lines: Int, muted: Bool = false, weight: NSFont.Weight = .regular) -> NSTextField {
            let label = panel.text(value,size: size,muted: muted,width: metadataWidth,weight: weight)
            label.maximumNumberOfLines = lines
            label.lineBreakMode = .byTruncatingTail
            label.toolTip = value
            return label
        }
        panel.add(metadataLabel(session.playback.title,size: compact ? 17 : 21,lines: compact ? 1 : 2,weight: .semibold),to: metadata)
        panel.add(metadataLabel(session.playback.artist,size: 13,lines: 1),to: metadata)
        if !compact {
            panel.add(metadataLabel(session.album.isEmpty ? session.playback.source : session.album,size: 12,lines: 2,muted: true),to: metadata)
        }
        panel.add(panel.row([art,metadata],spacing: gap),width: bodyWidth,height: artSize)
        let elapsed = panel.text("0:00", size: 11, muted: true, width: 40)
        let duration = panel.text(WidgetCatalog.formatTime(session.playback.duration), size: 11, muted: true, width: 40); duration.alignment = .right
        let slider = WidgetSlider(value: session.playback.position, max: max(1, session.playback.duration), label: "Playback position") { [weak self] seconds in self?.panel?.perform(.seek(session: session.id, seconds: seconds)) }
        slider.isEnabled = session.canSeek; slider.widthAnchor.constraint(equalToConstant: bodyWidth-100).isActive = true
        let progress = panel.row([elapsed,slider,duration])
        if !compact { panel.add(progress,width: bodyWidth,height: 26) }
        let shuffle = panel.iconButton("shuffle", label: "Shuffle") { [weak self] in self?.panel?.perform(.playback(session: session.id, command: .toggleShuffle)) }
        shuffle.isEnabled = session.shuffle != nil; shuffle.setButtonType(.toggle)
        let previous = panel.iconButton("backward.end.fill", label: "Previous track", size: 23) { [weak self] in self?.panel?.perform(.playback(session: session.id, command: .previous)) }; previous.isEnabled = session.canSkip
        let play = panel.iconButton("pause.fill", label: "Pause", size: 32) { [weak self] in self?.panel?.perform(.playback(session: session.id, command: .playPause)) }
        let next = panel.iconButton("forward.end.fill", label: "Next track", size: 23) { [weak self] in self?.panel?.perform(.playback(session: session.id, command: .next)) }; next.isEnabled = session.canSkip
        let repeatButton = panel.iconButton("repeat", label: "Repeat") { [weak self] in self?.panel?.perform(.playback(session: session.id, command: .cycleRepeat)) }; repeatButton.isEnabled = session.repeatMode != nil; repeatButton.setButtonType(.toggle)
        let transport = panel.row([shuffle, previous, play, next, repeatButton], spacing: 0); transport.distribution = .fillEqually
        for (control,id) in zip([shuffle,previous,play,next,repeatButton],["shuffle","previous","play","next","repeat"]) {
            control.identifier = NSUserInterfaceItemIdentifier("media.\(id)")
        }
        panel.add(transport, width: bodyWidth, height: 46)
        if compact {
            panel.add(progress,width: bodyWidth,height: 26)
            let detail = panel.label(session.album.isEmpty ? session.playback.source : session.album,size: 12,muted: true)
            detail.maximumNumberOfLines = 2; detail.lineBreakMode = .byTruncatingTail
            detail.toolTip = detail.stringValue
        }
        panel.refreshers.append { [weak self, weak elapsed, weak slider, weak play, weak shuffle, weak repeatButton] in
            guard let current = self?.panel?.state.mediaSessions.first(where: { $0.id == session.id }) else { return }
            elapsed?.stringValue = WidgetCatalog.formatTime(current.playback.position)
            play?.symbolName = current.playback.isPlaying ? "pause.fill" : "play.fill"; play?.setAccessibilityLabel(current.playback.isPlaying ? "Pause" : "Play")
            if slider?.cell?.isHighlighted != true { slider?.doubleValue = current.playback.position }
            shuffle?.state = current.shuffle == true ? .on : .off; shuffle?.setAccessibilityLabel(current.shuffle == true ? "Shuffle on" : "Shuffle off")
            repeatButton?.symbolName = current.repeatMode == .one ? "repeat.1" : "repeat"
            repeatButton?.state = current.repeatMode != nil && current.repeatMode != .off ? .on : .off
            repeatButton?.setAccessibilityLabel("Repeat " + (current.repeatMode?.rawValue ?? "unavailable"))
        }
        panel.rule()
        if state.providerStatuses.contains(where: { $0.id == "appleMusic" && $0.needsAttention }) {
            panel.add(panel.button("Enable Apple Music controls…") { [weak self] in self?.panel?.perform(.authorizeMusic) }, width: bodyWidth, height: 30)
        }
        panel.add(panel.choices(["Playing", "Up next"], selected: mediaTab, width: bodyWidth) { [weak self] index in self?.mediaTab = index; self?.panel?.rebuild() })
        if mediaTab == 0 {
            let now = panel.actionRow(session.playback.title, symbol: "music.note") { [weak self] in if session.providerID == "appleMusic" { self?.panel?.openApp("com.apple.Music") } }
            now.subtitle = session.playback.source; now.trailing = WidgetCatalog.formatTime(session.playback.duration)
            panel.add(now, width: bodyWidth, height: 44)
        } else {
            panel.label("This provider does not expose its Up Next queue to the bar.", size: 11, muted: true)
            if session.providerID == "appleMusic" { panel.add(panel.button("View queue in Music") { [weak self] in self?.panel?.openApp("com.apple.Music") }, width: bodyWidth, height: 30) }
        }

    }
    @objc private func mediaSourceChanged(_ sender: NSPopUpButton) {
        guard let panel, panel.state.mediaSessions.indices.contains(sender.indexOfSelectedItem) else { return }
        selectedSession = panel.state.mediaSessions[sender.indexOfSelectedItem].id
        panel.rebuild()
    }

}
