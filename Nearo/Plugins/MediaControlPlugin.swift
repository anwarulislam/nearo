//
//  MediaControlPlugin.swift
//  Nearo
//

import Foundation
import Combine

/// The last position reported by the player and the clock used to advance it between packets.
struct PlaybackTimeline: Sendable, Equatable {
    var length = 0
    var position = 0
    var reportedAt = Date.distantPast
    var rate = 1.0
    var canSeek = false

    func milliseconds(at date: Date, playing: Bool) -> Int {
        let elapsed = playing && reportedAt != .distantPast ? max(0, date.timeIntervalSince(reportedAt)) : 0
        let projected = max(0, Double(position) + elapsed * rate * 1000)
        return projected >= Double(length) ? max(0, length) : Int(projected)
    }
}

/// What the phone's media player is currently doing.
public struct NowPlaying: Sendable, Equatable {
    public var player: String = ""
    public var title: String = ""
    public var artist: String = ""
    public var album: String = ""

    var timeline = PlaybackTimeline()

    /// Track length in milliseconds, 0 when unknown (live streams).
    public var length: Int {
        get { timeline.length }
        set { timeline.length = newValue }
    }
    /// Playback position in milliseconds.
    public var position: Int {
        get { timeline.position }
        set { timeline.position = newValue }
    }

    public var isPlaying: Bool = false
    public var volume: Int = 0

    public var canPlay: Bool = false
    public var canPause: Bool = false
    public var canGoNext: Bool = false
    public var canGoPrevious: Bool = false
    public var canSeek: Bool {
        get { timeline.canSeek }
        set { timeline.canSeek = newValue }
    }

    public var hasTrack: Bool { !title.isEmpty }

    /// Elapsed time as mm:ss, empty when the length is unknown.
    public var elapsedLabel: String {
        guard length > 0 else { return "" }
        let seconds = max(0, position / 1000)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Controls the phone's media player (upstream's `mprisremote`).
///
/// Commands go out as `kdeconnect.mpris.request`; state comes back as
/// `kdeconnect.mpris`. Album art, when offered, arrives as a separate payload
/// flagged by `transferringAlbumArt`.
public final class MediaControlPlugin: ObservableObject, NearoPlugin, @unchecked Sendable {

    public let supportedPacketTypes = ["kdeconnect.mpris"]

    /// Current track per device id.
    @Published public private(set) var nowPlaying: [String: NowPlaying] = [:]

    /// Album art per device id, decoded from the payload when offered.
    @Published public private(set) var albumArt: [String: Data] = [:]

    /// Players advertised by the peer.
    @Published public private(set) var players: [String: [String]] = [:]

    /// The art each device's current track points to, as the phone names it.
    private var albumArtURLs: [String: String] = [:]

    public init() {}

    public func onConnected(connection: DeviceConnection) {
        requestState(connection: connection)
    }

    public func onDisconnected(connection: DeviceConnection) {
        guard let deviceId = connection.peerDeviceInfo?.deviceId else { return }
        nowPlaying.removeValue(forKey: deviceId)
        albumArt.removeValue(forKey: deviceId)
        albumArtURLs.removeValue(forKey: deviceId)
        players.removeValue(forKey: deviceId)
    }

    public func handlePacket(connection: DeviceConnection, packet: NetworkPacket) {
        guard packet.type == "kdeconnect.mpris",
              let deviceId = connection.peerDeviceInfo?.deviceId else { return }

        if packet.has("playerList") {
            let list = packet.stringArray(for: "playerList")
            players[deviceId] = list
            guard let player = nowPlaying[deviceId]?.player, list.contains(player) else {
                nowPlaying.removeValue(forKey: deviceId)
                albumArt.removeValue(forKey: deviceId)
                albumArtURLs.removeValue(forKey: deviceId)
                if let first = list.first { requestMetadata(first, connection: connection) }
                return
            }
            requestMetadata(player, connection: connection)
            return
        }

        var state = nowPlaying[deviceId] ?? NowPlaying()
        let newPlayer = packet.string(for: "player") ?? state.player
        let newTitle = packet.string(for: "title") ?? state.title
        if newPlayer != state.player || newTitle != state.title {
            state.timeline = PlaybackTimeline()
        }
        let now = Date()
        if packet.has("pos") || packet.has("isPlaying") || packet.has("rate") {
            state.position = packet.has("pos") ? packet.int(for: "pos") : state.timeline.milliseconds(at: now, playing: state.isPlaying)
            state.timeline.reportedAt = now
        }
        if packet.has("rate") {
            let rate = packet.double(for: "rate", default: 1)
            state.timeline.rate = rate.isFinite ? rate : 1
        }
        state.player = newPlayer
        if let title = packet.string(for: "title") { state.title = title }
        if let artist = packet.string(for: "artist") { state.artist = artist }
        if let album = packet.string(for: "album") { state.album = album }

        if packet.body["length"] != nil { state.length = packet.int(for: "length") }
        if packet.body["volume"] != nil { state.volume = packet.int(for: "volume") }
        if packet.body["isPlaying"] != nil { state.isPlaying = packet.bool(for: "isPlaying") }

        if packet.body["canPlay"] != nil { state.canPlay = packet.bool(for: "canPlay") }
        if packet.body["canPause"] != nil { state.canPause = packet.bool(for: "canPause") }
        if packet.body["canGoNext"] != nil { state.canGoNext = packet.bool(for: "canGoNext") }
        if packet.body["canGoPrevious"] != nil { state.canGoPrevious = packet.bool(for: "canGoPrevious") }
        if packet.body["canSeek"] != nil { state.canSeek = packet.bool(for: "canSeek") }

        nowPlaying[deviceId] = state

        // The phone names the track's art by URL and sends the image only when
        // asked for that URL, as a payload on a later packet.
        if !packet.bool(for: "transferringAlbumArt"), let url = packet.string(for: "albumArtUrl"),
           url != albumArtURLs[deviceId] {
            albumArtURLs[deviceId] = url
            if url.isEmpty {
                albumArt.removeValue(forKey: deviceId)
            } else {
                connection.send(packet: NetworkPacket(
                    type: "kdeconnect.mpris.request",
                    body: ["player": state.player, "albumArtUrl": url]
                ))
            }
        }
    }

    public func handlePayload(connection: DeviceConnection, packet: NetworkPacket, fileURL: URL) {
        guard packet.type == "kdeconnect.mpris",
              let deviceId = connection.peerDeviceInfo?.deviceId,
              packet.bool(for: "transferringAlbumArt"),
              // Art for a track that's already been replaced is stale.
              packet.string(for: "albumArtUrl") == albumArtURLs[deviceId],
              let data = try? Data(contentsOf: fileURL) else { return }

        albumArt[deviceId] = data
    }

    // MARK: - Commands

    public func requestState(connection: DeviceConnection) {
        connection.send(packet: NetworkPacket(type: "kdeconnect.mpris.request", body: ["requestPlayerList": true]))
    }

    private func requestMetadata(_ player: String, connection: DeviceConnection) {
        connection.send(packet: NetworkPacket(type: "kdeconnect.mpris.request",
            body: ["player": player, "requestNowPlaying": true, "requestVolume": true]))
    }

    func setPosition(_ milliseconds: Int, connection: DeviceConnection) {
        guard let id = connection.peerDeviceInfo?.deviceId, var state = nowPlaying[id],
              !state.player.isEmpty, state.canSeek, state.length > 0 else { return }
        state.position = min(max(0, milliseconds), state.length)
        state.timeline.reportedAt = .now
        nowPlaying[id] = state
        connection.send(packet: NetworkPacket(type: "kdeconnect.mpris.request",
            body: ["SetPosition": state.position, "player": state.player]))
    }

    /// Sends a transport action: Play, Pause, PlayPause, Next or Previous.
    public func sendAction(_ action: String, connection: DeviceConnection) {
        var body: [String: Any] = ["action": action]
        if let player = currentPlayer(connection: connection) {
            body["player"] = player
        }
        connection.send(packet: NetworkPacket(type: "kdeconnect.mpris.request", body: body))
    }

    public func setVolume(_ volume: Int, connection: DeviceConnection) {
        var body: [String: Any] = ["setVolume": max(0, min(100, volume))]
        if let player = currentPlayer(connection: connection) {
            body["player"] = player
        }
        connection.send(packet: NetworkPacket(type: "kdeconnect.mpris.request", body: body))
    }

    /// Seeks by a relative offset in milliseconds.
    public func seek(offsetMilliseconds: Int, connection: DeviceConnection) {
        var body: [String: Any] = ["Seek": offsetMilliseconds]
        if let player = currentPlayer(connection: connection) {
            body["player"] = player
        }
        connection.send(packet: NetworkPacket(type: "kdeconnect.mpris.request", body: body))
    }

    private func currentPlayer(connection: DeviceConnection) -> String? {
        guard let deviceId = connection.peerDeviceInfo?.deviceId,
              let player = nowPlaying[deviceId]?.player,
              !player.isEmpty else { return nil }
        return player
    }
}
