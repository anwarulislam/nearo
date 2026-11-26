import SwiftUI
import UniformTypeIdentifiers

struct OverviewPane: View {
    @Bindable var device: DeviceViewModel
    var openDeviceSettings: () -> Void = {}
    var onClipboard: () -> Void = {}
    let onSelectSection: (DeviceSection) -> Void
    @Environment(\.isCompactWorkspace) private var isCompactWorkspace
    @Environment(\.workspaceTheme) private var theme
    @State private var targetingFileArea = false
    @Environment(\.openWindow) private var openWindow
    private let files = PhoneFilesController.shared

    var body: some View {
        GeometryReader { geometry in
            let narrow = geometry.size.width < 605 || isCompactWorkspace
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    HStack(spacing: 0) {
                        quickAction("Ring", .ring) { device.findMyPhone() }
                        quickAction("Clipboard", .clipboard, action: onClipboard)
                        quickAction("Send Files", .send) { chooseFiles() }
                        quickAction("Remote Input", .monitor) {
                            openWindow(id: "remote-input", value: device.id)
                        }
                        quickAction("Phone Drive", .drive) {
                            if files.driveState(for: device.id) == .mounted { files.showInFinder(device.id) }
                            else { onSelectSection(.files) }
                        }
                    }
                    .frame(maxWidth: 500).frame(maxWidth: .infinity)
                    .padding(.top, 12).padding(.bottom, 30)

                    let layout = narrow ? AnyLayout(VStackLayout(spacing: 23)) : AnyLayout(HStackLayout(alignment: .top, spacing: 18))
                    layout {
                        VStack(alignment: .leading, spacing: 23) {
                            group("Notifications", section: .notifications) {
                                if device.notifications.isEmpty { empty("All caught up", .bell) }
                                ForEach(device.notifications.prefix(3)) { item in
                                    if item.id != device.notifications.first?.id { Divider() }
                                    NotificationPreviewRow(item: item)
                                }
                            }
                            group("Recent Messages", section: .messages) {
                                if let thread = device.smsThreads.first {
                                    Button { onSelectSection(.messages) } label: {
                                        HStack(spacing: 9) {
                                            InitialsAvatar(name: device.title(for: thread), size: 36, photo: device.photo(for: thread))
                                            VStack(alignment: .leading) {
                                                Text(device.title(for: thread)).fontWeight(.semibold)
                                                Text(thread.snippet).font(.caption).foregroundStyle(.secondary)
                                            }.lineLimit(1)
                                            Spacer(minLength: 2)
                                            Text(MessageDate.short(thread.lastDate)).font(.caption2).foregroundStyle(.secondary)
                                            WorkspaceIcon.chevron.view(12)
                                        }.padding(12).contentShape(.rect)
                                    }.buttonStyle(.plain)
                                } else { empty("No recent messages", .message) }
                            }
                        }.frame(maxWidth: .infinity)

                        VStack(alignment: .leading, spacing: 23) {
                            group("File Transfer", section: .files) {
                                SendDropArea(device: device, showsGuide: false)
                                    .background(theme.color(.accent).opacity(targetingFileArea ? 0.12 : 0),
                                                in: .rect(cornerRadius: 7))
                                    .overlay {
                                        if targetingFileArea {
                                            RoundedRectangle(cornerRadius: 7)
                                                .strokeBorder(theme.color(.accent), style: StrokeStyle(dash: [4, 3]))
                                                .allowsHitTesting(false)
                                        }
                                    }
                                    .dropDestination(for: OverviewFileDrop.self) { files, _ in
                                        guard !files.isEmpty else { return false }
                                        device.sendFiles(files.map(\.url))
                                        onSelectSection(.files)
                                        return true
                                    } isTargeted: { targetingFileArea = $0 }
                                    .padding(11)
                            }
                            group("On Your Phone") {
                                libraryRow(.contacts, count: device.contacts.count, noun: "contacts", colors: [.brown])
                                Divider()
                                libraryRow(.photos, count: device.photos.count, noun: "photos", colors: [.pink, .orange, .green, .blue])
                                Divider()
                                libraryRow(.commands, count: device.commands.count, noun: "commands", colors: [.black, .gray])
                            }
                        }
                        .frame(width: narrow ? nil : min(900, geometry.size.width - 48) * 0.44)
                    }

                    HStack(spacing: 5) {
                        WorkspaceIcon.shield.view(13)
                        Text(device.isViaTailscale ? "Connected through Tailscale." : device.isViaBluetooth ? "Connected over Bluetooth." : "Your devices communicate directly over the local network.")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 26)
                    if device.hasNowPlaying { NowPlayingPanel(device: device).padding(.bottom, 18) }
                    RemoteInputRow()
                }
                .frame(maxWidth: 900)
                .padding(24).frame(maxWidth: .infinity)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 18) {
            Group {
                if device.deviceType == .phone {
                    HandsetArtwork(preview: device.handset)
                } else { DeviceHero(type: device.deviceType) }
            }.frame(width: 104).accessibilityHidden(device.deviceType != .phone)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    ConnectionDot(connected: true)
                    Text("Connected").font(.caption.weight(.semibold)).foregroundStyle(WorkspaceColor.green)
                }
                Text(device.name).font(.system(size: 29, weight: .semibold)).tracking(-0.8)
                Text(device.deviceType == .phone ? "Android phone" : device.deviceType.rawValue.capitalized)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    if let percent = device.batteryPercent {
                        HStack(spacing: 4) {
                            WorkspaceIcon.battery.view(21).foregroundStyle(WorkspaceColor.green)
                            Text("\(percent)%").fontWeight(.medium)
                        }.help(device.isCharging ? "Charging" : "Battery level")
                    }
                    HStack(spacing: 4) {
                        if !device.isViaBluetooth { WorkspaceIcon.wifi.view(16) }
                        Text(device.isViaBluetooth ? "Bluetooth" : device.isViaTailscale ? "Tailscale" : "Wi-Fi")
                    }
                    if let network = device.networkType, !network.isEmpty {
                        HStack(spacing: 4) { WorkspaceIcon.signal.view(16); Text(network) }
                    }
                }.font(.callout).padding(.top, 7)
                Text(device.isViaBluetooth ? "Connected over Bluetooth" : device.isViaTailscale ? "Connected over Tailscale" : "Connected over your local network")
                    .font(.caption).foregroundStyle(.secondary)
                    .help([device.lanAddress, device.bluetoothAddress].compactMap { $0 }.joined(separator: " · "))
            }
            Spacer(minLength: 0)
            VStack {
                Button(action: openDeviceSettings) {
                    HStack(spacing: 5) { WorkspaceIcon.settings.view(14); Text("Device Settings…") }
                }.glassButton()
                Spacer()
            }.padding(.top, 10)
        }
        .frame(minHeight: 163)
    }

    private func chooseFiles() { device.sendFiles(FilePicker.chooseFiles(sendingTo: device.name)) }

    private func quickAction(_ label: String, _ icon: WorkspaceIcon, action: @escaping () -> Void) -> some View {
        OverviewActionButton(title: label, icon: icon, action: action)
            .frame(maxWidth: .infinity)
    }

    private func group<Content: View>(_ title: String, section: DeviceSection? = nil,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if let section {
                    Button { onSelectSection(section) } label: {
                        HStack(spacing: 3) { Text("Show All"); WorkspaceIcon.chevron.view(11) }
                    }
                    .buttonStyle(.link).font(.callout)
                    .accessibilityLabel("Show all " + section.title.lowercased())
                }
            }
            VStack(spacing: 0) { content() }
                .frame(maxWidth: .infinity)
                .workspaceCard()
        }
    }

    private func empty(_ title: String, _ icon: WorkspaceIcon) -> some View {
        VStack(spacing: 6) { icon.view(23); Text(title).font(.callout) }
            .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(18)
    }

    private func libraryRow(_ section: DeviceSection, count: Int, noun: String, colors: [Color]) -> some View {
        Button { onSelectSection(section) } label: {
            HStack(spacing: 10) {
                section.icon.view().foregroundStyle(.white).frame(width: 30, height: 30)
                    .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: .rect(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title).fontWeight(.medium)
                    Text("\(count) \(noun)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                WorkspaceIcon.chevron.view(13).foregroundStyle(.secondary)
            }.padding(11).contentShape(.rect)
        }.buttonStyle(.plain)
    }
}

private struct OverviewFileDrop: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .fileURL) { data in
            guard let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return OverviewFileDrop(url: url)
        }
    }
}

struct SendDropArea: View {
    @Environment(\.workspaceTheme) private var theme
    let device: DeviceViewModel
    var showsGuide = true
    var body: some View {
        Button { device.sendFiles(FilePicker.chooseFiles(sendingTo: device.name)) } label: {
            VStack(spacing: 5) {
                WorkspaceIcon.upload.view(24).foregroundStyle(theme.color(.accent))
                Text("Drop files here or \(Text("browse").foregroundStyle(theme.color(.accent)))")
                Text("Send directly to \(device.name) · No cloud required")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .font(.callout).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(.vertical, 17).padding(.horizontal, 8)
            .overlay {
                if showsGuide {
                    RoundedRectangle(cornerRadius: 7).strokeBorder(.secondary.opacity(0.32), style: StrokeStyle(dash: [4, 3]))
                }
            }
            .contentShape(.rect)
        }.buttonStyle(.plain)
    }
}

// MARK: - Now playing

private struct NowPlayingPanel: View {
    @Bindable var device: DeviceViewModel
    @State private var draftVolume: Float = 0.5
    @State private var isEditingVolume = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelHeader("Now Playing")
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    artwork
                    VStack(alignment: .leading, spacing: 3) {
                        Text(device.nowPlayingTitle ?? "")
                            .font(.headline)
                            .lineLimit(1)
                        if let subtitle {
                            Text(subtitle)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 18) {
                        Button("Previous", systemImage: "backward.fill") { device.previousMedia() }
                        Button(device.nowPlayingIsPlaying ? "Pause" : "Play",
                               systemImage: device.nowPlayingIsPlaying ? "pause.fill" : "play.fill") {
                            device.playPauseMedia()
                        }
                        .font(.title2)
                        .contentTransition(.symbolEffect(.replace))
                        Button("Next", systemImage: "forward.fill") { device.nextMedia() }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .font(.title3)
                }

                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: $draftVolume, in: 0...1) { Text("Volume") } onEditingChanged: { editing in
                        isEditingVolume = editing
                        // Send once when the drag ends rather than on every tick.
                        if !editing { device.setVolume(draftVolume) }
                    }
                    .labelsHidden()
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                }
                .disabled(!device.canSetVolume)
                .help(device.canSetVolume ? "Media volume on \(device.name)" : "Start playing something on \(device.name) to change its volume")
            }
            .padding(16)
            .glassPanel()
        }
        .onAppear { draftVolume = device.volume }
        .onChange(of: device.volume) {
            if !isEditingVolume { draftVolume = device.volume }
        }
    }

    private var subtitle: String? {
        let parts = [device.nowPlayingArtist, device.nowPlayingAlbum].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var artwork: some View {
        if let image = device.albumArt {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 56)
                .clipShape(.rect(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "music.note")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 56, height: 56)
                .background(.quaternary, in: .rect(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Notifications

private struct NotificationPreviewRow: View {
    let item: PhoneNotification

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            NotificationBadge(item: item)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.appName).font(.caption2).foregroundStyle(.secondary)
                Text(item.title).font(.callout.weight(.semibold)).lineLimit(1)
                if !item.text.isEmpty {
                    Text(item.text).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                if let code = item.code { CopyCodeButton(code: code).buttonStyle(.link) }
            }
            Spacer(minLength: 0)
            Text(MessageDate.short(item.date)).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Remote input

/// Shown only while Accessibility access is missing; once granted there's nothing to say.
private struct RemoteInputRow: View {
    @State private var isTrusted = InputSynthesizer.shared.isAccessibilityTrusted
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        Group {
            if !isTrusted {
                HStack(spacing: 14) {
                    Image(systemName: "cursorarrow.motionlines")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use your phone as a trackpad")
                            .fontWeight(.semibold)
                        Text("Nearo needs Accessibility access to move the pointer and type for your phone.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button("Allow…") { InputSynthesizer.shared.openAccessibilitySettings() }
                }
                .padding(16)
                .glassPanel()
            }
        }
        // Re-check when the window regains focus, e.g. after visiting System Settings.
        .onChange(of: controlActiveState) {
            isTrusted = InputSynthesizer.shared.isAccessibilityTrusted
        }
    }
}

#if DEBUG
#Preview {
    OverviewPane(device: .mockConnectedPhone(), onSelectSection: { _ in })
        .frame(width: 900, height: 760)
}
#endif

private struct HandsetArtwork: View {
    let preview: HandsetPreview

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: "Handset").resizable().frame(width: 78, height: 154)
            if let wallpaper = preview.wallpaper {
                Image(nsImage: wallpaper).resizable().scaledToFill()
                    .frame(width: 67, height: 145)
                    .clipShape(.rect(cornerRadius: 12)).offset(x: 4, y: 4).accessibilityHidden(true)
                Circle().fill(.black.opacity(0.85)).frame(width: 5, height: 5).offset(x: 35, y: 9)
                Capsule().fill(.white.opacity(0.9)).frame(width: 23, height: 2).offset(x: 26, y: 142)
            }
            TimelineView(.periodic(from: Date(timeIntervalSince1970: -(preview.clock?.adjustment ?? 0)), by: 60)) { tick in
                Text(verbatim: preview.time(at: tick.date))
                    .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(preview.wallpaper == nil ? Color(red: 0.18, green: 0.28, blue: 0.34) : .white)
                    .shadow(color: .black.opacity(preview.wallpaper == nil ? 0 : 0.85), radius: 2, y: 1)
                    .accessibilityLabel(preview.clockDescription + ", " + preview.time(at: tick.date))
                    .frame(width: 67).offset(x: 4, y: 24)
            }
        }
        .shadow(color: .black.opacity(0.22), radius: 4, y: 4)
        .help(preview.helpText)
        .task(id: ObjectIdentifier(preview)) {
            while !Task.isCancelled {
                preview.refreshIfNeeded()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
}

private struct OverviewActionButton: View {
    @Environment(\.workspaceTheme) private var theme
    let title: String
    let icon: WorkspaceIcon
    let action: () -> Void
    @State private var hovering = false
    @State private var highlight: UnitPoint = .top
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(MotionPreference.key) private var appReducesMotion = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                let symbol = icon.view(23).foregroundStyle(theme.color(.accent))
                    .frame(width: 49, height: 49)
                Group {
                    if #available(macOS 26, *) {
                        symbol.glassEffect(.regular.interactive(), in: Circle())
                    } else {
                        symbol.background(.regularMaterial, in: Circle())
                            .overlay { Circle().strokeBorder(.primary.opacity(hovering ? 0.22 : 0.10)) }
                    }
                }
                .overlay {
                    Circle()
                        .fill(RadialGradient(colors: [.white.opacity(0.22), .clear], center: highlight, startRadius: 0, endRadius: 33))
                        .opacity(hovering ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .onContinuousHover { phase in
                    if case .active(let point) = phase {
                        highlight = UnitPoint(x: point.x / 49, y: point.y / 49)
                    }
                }
                .scaleEffect(hovering && !reduceMotion && !appReducesMotion ? 1.07 : 1)
                Text(title).font(.caption).foregroundStyle(hovering ? .primary : .secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(reduceMotion || appReducesMotion ? nil : .spring(duration: 0.22), value: hovering)
    }
}
