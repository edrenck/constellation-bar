import AppKit
import CoreAudio

/// Feature-specific content in the shared native widget panel.
extension MiniAppPanel {
    func buildMedia() {
        let sessions = state.mediaSessions
        if !sessions.contains(where: { $0.id == selectedSession }) { selectedSession = sessions.first(where: { $0.playback.isPlaying })?.id ?? sessions.first?.id ?? "" }
        if sessions.count > 1 {
            let popup = NSPopUpButton(); popup.addItems(withTitles: sessions.map { "\($0.playback.source) · \($0.playback.title.prefix(32))" })
            popup.selectItem(at: sessions.firstIndex(where: { $0.id == selectedSession }) ?? 0)
            popup.target = self; popup.action = #selector(mediaSourceChanged(_:)); add(popup, width: bodyWidth)
        }
        guard let session = sessions.first(where: { $0.id == selectedSession }) else {
            let glyph = PanelGlyph(); glyph.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil); glyph.color = config.theme.muted; glyph.tile = config.theme.surface
            add(row([NSView(), glyph, NSView()]), width: bodyWidth, height: 80); glyph.widthAnchor.constraint(equalToConstant: 80).isActive = true
            label(state.mediaNeedsAttention ? "Music needs attention" : "Nothing playing", size: 23)
            for provider in state.providerStatuses where ["appleMusic", "browser"].contains(provider.id) { label(provider.message, muted: true) }
            if config.providerPreferences.includes("appleMusic") {
                add(button("Open Apple Music") { [weak self] in self?.openApp("com.apple.Music") }, width: bodyWidth, height: 34)
                add(button("Allow Apple Music access") { [weak self] in self?.perform(.authorizeMusic) }, width: bodyWidth, height: 34)
            }
            add(button("Browser setup guide") { [weak self] in self?.openBrowserGuide() }, width: bodyWidth, height: 34)
            return
        }
        let art = NSImageView(); art.image = session.artwork.flatMap(NSImage.init(data:)) ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: "Artwork unavailable")
        art.imageScaling = .scaleProportionallyUpOrDown; art.wantsLayer = true; art.layer?.cornerRadius = 9; art.layer?.masksToBounds = true
        art.widthAnchor.constraint(equalToConstant: 148).isActive = true; art.heightAnchor.constraint(equalToConstant: 148).isActive = true
        let metadata = column(width: bodyWidth-166, spacing: 8)
        add(text("NOW PLAYING", size: 10, muted: true), to: metadata)
        add(text(session.playback.title, size: 21, width: bodyWidth-166, weight: .semibold), to: metadata)
        add(text(session.playback.artist, size: 13, width: bodyWidth-166), to: metadata)
        add(text(session.album.isEmpty ? session.playback.source : session.album, size: 12, muted: true, width: bodyWidth-166), to: metadata)
        add(row([art, metadata], spacing: 18), height: 148)
        let elapsed = text("0:00", size: 11, muted: true, width: 40)
        let duration = text(WidgetCatalog.formatTime(session.playback.duration), size: 11, muted: true, width: 40); duration.alignment = .right
        let slider = WidgetSlider(value: session.playback.position, max: max(1, session.playback.duration), label: "Playback position") { [weak self] seconds in self?.perform(.seek(session: session.id, seconds: seconds)) }
        slider.isEnabled = session.canSeek; slider.widthAnchor.constraint(equalToConstant: bodyWidth-100).isActive = true
        add(row([elapsed, slider, duration]), width: bodyWidth, height: 26)
        let shuffle = iconButton("shuffle", label: "Shuffle") { [weak self] in self?.perform(.playback(session: session.id, command: .toggleShuffle)) }
        shuffle.isEnabled = session.shuffle != nil; shuffle.setButtonType(.toggle)
        let previous = iconButton("backward.end.fill", label: "Previous track", size: 23) { [weak self] in self?.perform(.playback(session: session.id, command: .previous)) }; previous.isEnabled = session.canSkip
        let play = iconButton("pause.fill", label: "Pause", size: 32) { [weak self] in self?.perform(.playback(session: session.id, command: .playPause)) }
        let next = iconButton("forward.end.fill", label: "Next track", size: 23) { [weak self] in self?.perform(.playback(session: session.id, command: .next)) }; next.isEnabled = session.canSkip
        let repeatButton = iconButton("repeat", label: "Repeat") { [weak self] in self?.perform(.playback(session: session.id, command: .cycleRepeat)) }; repeatButton.isEnabled = session.repeatMode != nil; repeatButton.setButtonType(.toggle)
        let transport = row([shuffle, previous, play, next, repeatButton], spacing: 0); transport.distribution = .fillEqually
        add(transport, width: bodyWidth, height: 46)
        refreshers.append { [weak self, weak elapsed, weak slider, weak play, weak shuffle, weak repeatButton] in
            guard let current = self?.state.mediaSessions.first(where: { $0.id == session.id }) else { return }
            elapsed?.stringValue = WidgetCatalog.formatTime(current.playback.position)
            play?.symbolName = current.playback.isPlaying ? "pause.fill" : "play.fill"; play?.setAccessibilityLabel(current.playback.isPlaying ? "Pause" : "Play")
            if slider?.cell?.isHighlighted != true { slider?.doubleValue = current.playback.position }
            shuffle?.state = current.shuffle == true ? .on : .off; shuffle?.setAccessibilityLabel(current.shuffle == true ? "Shuffle on" : "Shuffle off")
            repeatButton?.symbolName = current.repeatMode == .one ? "repeat.1" : "repeat"
            repeatButton?.state = current.repeatMode != nil && current.repeatMode != .off ? .on : .off
            repeatButton?.setAccessibilityLabel("Repeat " + (current.repeatMode?.rawValue ?? "unavailable"))
        }
        rule()
        add(choices(["Playing", "Up next"], selected: mediaTab, width: bodyWidth) { [weak self] index in self?.mediaTab = index; self?.rebuild() })
        if mediaTab == 0 {
            let now = actionRow(session.playback.title, symbol: "music.note") { [weak self] in if session.providerID == "appleMusic" { self?.openApp("com.apple.Music") } }
            now.subtitle = session.playback.source; now.trailing = WidgetCatalog.formatTime(session.playback.duration)
            add(now, width: bodyWidth, height: 44)
        } else {
            label("This provider does not expose its Up Next queue to the bar.", size: 11, muted: true)
            if session.providerID == "appleMusic" { add(button("View queue in Music") { [weak self] in self?.openApp("com.apple.Music") }, width: bodyWidth, height: 30) }
        }
        rule()
        add(actionRow(state.audio.output?.name ?? "Audio output", symbol: state.audio.output?.symbol ?? "headphones") { [weak self] in self?.onOpenAudio?() }, width: bodyWidth, height: 36)
    }
    @objc func mediaSourceChanged(_ sender: NSPopUpButton) {
        guard state.mediaSessions.indices.contains(sender.indexOfSelectedItem) else { return }
        selectedSession = state.mediaSessions[sender.indexOfSelectedItem].id; rebuild()
    }
    func openBrowserGuide() {
        if let url = Bundle.main.url(forResource: "BrowserMedia-README", withExtension: "md") { NSWorkspace.shared.open(url) }
        else { status.stringValue = "See extensions/browser-media/README.md in the project." }
    }

}
