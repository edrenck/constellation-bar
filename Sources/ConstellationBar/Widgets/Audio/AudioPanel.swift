import AppKit
import CoreAudio

/// Feature-specific content in the shared native widget panel.
extension MiniAppPanel {
    func buildAudio() {
        add(choices(["Output", "Input"], selected: selectedTab, width: bodyWidth) { [weak self] index in self?.selectedTab = index; self?.rebuild() })
        let input = selectedTab == 1, id = selectedTab == 1 ? state.audio.inputID : state.audio.outputID
        let devices = state.audio.devices.filter { $0.isInput == input }
        label(input ? "Input volume" : "Output volume", size: 13)
        if let selected = devices.first(where: { $0.id == id }) {
            let glyph = PanelGlyph(); glyph.image = NSImage(systemSymbolName: input ? "mic" : "speaker.wave.2", accessibilityDescription: nil); glyph.color = config.theme.foreground
            glyph.widthAnchor.constraint(equalToConstant: 24).isActive = true; glyph.heightAnchor.constraint(equalToConstant: 24).isActive = true
            let percent = text("", size: 11, width: 38); percent.alignment = .right
            let slider = WidgetSlider(value: selected.volume ?? 0, max: 1, label: input ? "Input volume" : "Output volume") { [weak self] value in self?.perform(.audioVolume(id, input: input, value: value)) }; slider.isEnabled = selected.canSetVolume
            slider.widthAnchor.constraint(equalToConstant: bodyWidth-136).isActive = true
            let mute = iconButton("speaker.slash", label: "Mute") { [weak self] in
                guard let self else { return }; let muted = self.state.audio.devices.first { $0.id == id && $0.isInput == input }?.muted ?? false
                self.perform(.audioMute(id, input: input, muted: !muted))
            }; mute.treatment = .outline; mute.isEnabled = selected.canMute; mute.setButtonType(.toggle)
            mute.widthAnchor.constraint(equalToConstant: 44).isActive = true; mute.heightAnchor.constraint(equalToConstant: 36).isActive = true
            add(row([glyph, slider, percent, mute]), width: bodyWidth, height: 42)
            refreshers.append { [weak self, weak slider, weak percent, weak mute] in
                guard let device = self?.state.audio.devices.first(where: { $0.id == id && $0.isInput == input }) else { return }
                percent?.stringValue = device.volume.map { "\(Int($0*100))%" } ?? "—"
                if slider?.cell?.isHighlighted != true { slider?.doubleValue = device.volume ?? 0 }
                mute?.state = device.muted == true ? .on : .off; mute?.setAccessibilityLabel(device.muted == true ? "Unmute" : "Mute")
            }
            if !selected.canSetVolume { label("Use this device’s hardware volume controls.", size: 11, muted: true) }
        }
        rule(); label(input ? "Select input device" : "Select output device", size: 13)
        let card = PanelCard(width: bodyWidth, theme: config.theme)
        for (index, device) in devices.enumerated() {
            if index > 0 { rule(width: bodyWidth-24, to: card.content) }
            let b = button(device.name, treatment: device.id == id ? .outline : .plain) { [weak self] in self?.perform(.audioDevice(device.id, input: input)) }
            b.leading = true; b.symbolName = device.symbol; b.subtitle = device.transport == kAudioDeviceTransportTypeBluetooth || device.transport == kAudioDeviceTransportTypeBluetoothLE ? "Bluetooth" : device.transport == kAudioDeviceTransportTypeBuiltIn ? "Built-in" : "Audio device"
            b.trailing = device.id == id ? "✓" : ""; b.statusColor = config.theme.blue
            b.setAccessibilityValue(b.subtitle + (device.id == id ? ", selected" : ""))
            add(b, width: bodyWidth-24, height: 58, to: card.content)
        }
        if devices.isEmpty { add(text("No devices available", muted: true), to: card.content) }
        add(card); rule()
        add(actionRow("Sound settings…", symbol: "slider.horizontal.3") { [weak self] in self?.openURL("x-apple.systempreferences:com.apple.Sound-Settings.extension") }, width: bodyWidth, height: 34)
    }

}
