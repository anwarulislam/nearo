import SwiftUI

struct MenuMediaTile: View {
    let device: DeviceViewModel
    let expand: () -> Void
    @State private var hovered = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Button(action: expand) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        MenuArtwork(device: device)
                        Spacer()
                        if hovered {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary).font(.system(size: 11, weight: .semibold))
                        }
                    }
                    Spacer(minLength: 0)
                    Text(device.hasNowPlaying ? device.nowPlayingTitle ?? "" : "Not Playing")
                        .font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    if device.hasNowPlaying, let artist = device.nowPlayingArtist, !artist.isEmpty {
                        Text(artist).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.primary.opacity(0.72)).lineLimit(1)
                    }
                }
                .padding(14)
                .padding(.bottom, 27)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(MenuGlassStyle(hovered: hovered, radius: 32))
            .accessibilityLabel("Now Playing")
            .accessibilityValue(device.nowPlayingTitle ?? "Not Playing")
            MenuTransport(device: device)
                .padding(.bottom, 14)
        }
        .onHover { hovered = $0 }
    }
}

private struct MenuArtwork: View {
    let device: DeviceViewModel

    var body: some View {
        ZStack {
            if device.hasNowPlaying, let art = device.albumArt {
                Image(nsImage: art).resizable().scaledToFill()
            } else {
                Color.primary.opacity(0.09)
                if device.hasNowPlaying { Image(systemName: "music.note").foregroundStyle(.secondary) }
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(.rect(cornerRadius: 9))
        .accessibilityHidden(true)
    }
}

private struct MenuTransport: View {
    let device: DeviceViewModel

    var body: some View {
        HStack(spacing: 10) {
            transport("Previous", "backward.fill", action: device.previousMedia)
            transport(device.nowPlayingIsPlaying ? "Pause" : "Play",
                      device.nowPlayingIsPlaying ? "pause.fill" : "play.fill", action: device.playPauseMedia)
            transport("Next", "forward.fill", action: device.nextMedia)
        }
        .disabled(!device.hasNowPlaying)
    }

    private func transport(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .bold))
                .frame(width: 30, height: 30).contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .help(title)
    }
}

struct MenuMediaDetail: View {
    let device: DeviceViewModel
    let back: () -> Void
    @State private var seekDraft: Double?
    @State private var volumeDraft: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MenuDetailHeader("Now Playing", back: back)
            HStack(spacing: 10) {
                MenuArtwork(device: device)
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.nowPlayingTitle ?? "Not Playing").font(.system(size: 12.5, weight: .semibold))
                    if let artist = device.nowPlayingArtist, !artist.isEmpty {
                        Text(artist).font(.callout).foregroundStyle(.secondary)
                    } else {
                        Text(device.name).font(.callout).foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let timeline = device.timeline
                let value = seekDraft ?? Double(timeline.milliseconds(at: context.date, playing: device.nowPlayingIsPlaying))
                VStack(spacing: 2) {
                    Slider(value: Binding(get: { value }, set: { seekDraft = $0 }),
                           in: 0...Double(max(1, timeline.length))) {
                        Text("Playback position")
                    } onEditingChanged: { editing in
                        if !editing, let position = seekDraft {
                            device.onSeek?(Int(position.rounded()))
                            seekDraft = nil
                        }
                    }
                    .labelsHidden()
                    .disabled(!device.hasNowPlaying || !timeline.canSeek || timeline.length <= 0)
                    .accessibilityValue(Self.time(Int(value)))
                    HStack {
                        Text(timeline.length > 0 ? Self.time(Int(value)) : "–:––")
                        Spacer()
                        Text(timeline.length > 0 ? "−" + Self.time(timeline.length - Int(value)) : "–:––")
                    }
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            MenuTransport(device: device).frame(maxWidth: .infinity)
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                Slider(value: Binding(get: { volumeDraft ?? Double(device.volume) }, set: { volumeDraft = $0 }),
                       in: 0...1) {
                    Text("Volume")
                } onEditingChanged: { editing in
                    if !editing, let volume = volumeDraft {
                        device.setVolume(Float(volume))
                        volumeDraft = nil
                    }
                }
                .labelsHidden()
                Image(systemName: "speaker.wave.3.fill")
            }
            .disabled(!device.canSetVolume)
        }
        .padding(14)
        .glassPanel(radius: 20)
        .onAppear { device.onRefreshMedia?() }
        .onChange(of: device.nowPlayingTitle) { seekDraft = nil }
    }

    private static func time(_ milliseconds: Int) -> String {
        let seconds = max(0, milliseconds / 1000)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
