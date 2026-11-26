//
//  DeviceViewModel.swift
//  Nearo
//
//  Observable view state for one device. Instances are cached by device ID in
//  NearoAppModel and updated in place, so view state survives model refreshes.
//

import SwiftUI
import AppKit
import Observation

public enum DeviceStatus: String, CaseIterable, Sendable {
    case connected = "Connected"
    case available = "Nearby"
    case offline = "Offline"
}

@Observable
@MainActor
public final class DeviceViewModel: Identifiable, Hashable {
    let handset: HandsetPreview
    public let id: String
    public var name: String
    public var deviceType: DeviceType
    public var status: DeviceStatus
    public var lastSeen: Date?

    public var batteryPercent: Int?
    public var isCharging: Bool
    public var networkType: String?
    public var cellularSignalStrength: Int?
    /// The phone's SIMs, when it has reported them.
    public var sims: [PhoneSIM] = []

    public var volume: Float
    public var isMuted: Bool
    var timeline = PlaybackTimeline()
    var onSeek: ((Int) -> Void)?
    var onRefreshMedia: (() -> Void)?
    public var nowPlayingTitle: String?
    public var nowPlayingArtist: String?
    public var nowPlayingAlbum: String?
    public var nowPlayingIsPlaying: Bool
    /// Decoded once when the bytes change, never in a view body.
    public private(set) var albumArt: NSImage?
    @ObservationIgnored private var albumArtData: Data?

    public var transfers: [TransferItem]
    public var smsThreads: [SMSConversation]
    /// The phone's contacts, for names and photos instead of numbers.
    public var contacts = ContactBook()
    var calls: [CallEntry] = []
    var isSyncingCalls = false
    var callSyncMessage: String?
    var onSyncCalls: ((_ automatic: Bool) -> Void)?
    /// The phone's photos gallery.
    public var photos: [PhonePhoto] = []
    public var isLoadingPhotos: Bool = false
    public var commands: [RemoteCommand]
    public var notifications: [PhoneNotification]

    /// A contact or number to start a new message with in MessagesPane.
    public var draftRecipient: (number: String, name: String?)?

    /// True between asking a nearby device to pair and it answering.
    public var isAwaitingPairing = false
    public var pairingVerificationCode: String?
    /// Whether the device accepts lock requests. KDE Connect for Android has no
    /// lock feature, so this is only true for desktops running KDE Connect.
    public var canLock = false
    var onRemoteInput: (([String: Any]) -> Bool)?
    /// Whether there's anything to set the volume of: on Android, a media app
    /// with an active session.
    public var canSetVolume = false
    /// Connected through Tailscale rather than the local network.
    public var isViaTailscale = false
    /// Connected through Bluetooth RFCOMM.
    public var isViaBluetooth = false
    /// Connected LAN IP or host address.
    public var lanAddress: String?
    /// Bluetooth MAC address.
    public var bluetoothAddress: String?

    // Action handlers injected by NearoAppModel or mocked
    public var onPing: (() -> Void)?
    var onShareClipboardText: ((String) -> Bool)?
    public var onSendClipboard: (() -> Void)?
    public var onSendFiles: (([URL]) -> Void)?
    public var onFindPhone: (() -> Void)?
    public var onLockDevice: (() -> Void)?
    public var onPair: (() -> Void)?
    public var onUnpair: (() -> Void)?
    public var onExecuteCommand: ((String) -> Void)?
    public var onSaveCommand: ((RemoteCommand) -> Void)?
    public var onDeleteCommand: ((String) -> Void)?
    public var onSendSMS: (([String], String, Int64?, Int64?) -> Void)?
    public var onRefreshMessages: (() -> Void)?
    public var onRefreshContacts: (() -> Void)?
    public var onRefreshPhotos: (() -> Void)?
    public var onStartMessageToContact: ((String, String?) -> Void)?
    public var onOpenThread: ((Int64) -> Void)?
    public var onLoadEarlierMessages: ((Int64) -> Void)?
    public var onSetVolume: ((Float) -> Void)?
    public var onMediaAction: ((String) -> Void)?
    public var onReplyToNotification: ((PhoneNotification, String) -> Void)?
    public var onDismissNotification: ((PhoneNotification) -> Void)?

    public init(
        id: String,
        name: String,
        deviceType: DeviceType = .phone,
        status: DeviceStatus = .connected,
        lastSeen: Date? = nil,
        batteryPercent: Int? = nil,
        isCharging: Bool = false,
        networkType: String? = nil,
        cellularSignalStrength: Int? = nil,
        volume: Float = 0.5,
        isMuted: Bool = false,
        nowPlayingTitle: String? = nil,
        nowPlayingArtist: String? = nil,
        nowPlayingAlbum: String? = nil,
        nowPlayingIsPlaying: Bool = false,
        transfers: [TransferItem] = [],
        smsThreads: [SMSConversation] = [],
        commands: [RemoteCommand] = [],
        notifications: [PhoneNotification] = []
    ) {
        self.handset = HandsetPreview(deviceID: id)
        self.id = id
        self.name = name
        self.deviceType = deviceType
        self.status = status
        self.lastSeen = lastSeen
        self.batteryPercent = batteryPercent
        self.isCharging = isCharging
        self.networkType = networkType
        self.cellularSignalStrength = cellularSignalStrength
        self.volume = volume
        self.isMuted = isMuted
        self.nowPlayingTitle = nowPlayingTitle
        self.nowPlayingArtist = nowPlayingArtist
        self.nowPlayingAlbum = nowPlayingAlbum
        self.nowPlayingIsPlaying = nowPlayingIsPlaying
        self.transfers = transfers
        self.smsThreads = smsThreads
        self.commands = commands
        self.notifications = notifications
    }

    public nonisolated static func == (lhs: DeviceViewModel, rhs: DeviceViewModel) -> Bool {
        lhs.id == rhs.id
    }

    public nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public var isConnected: Bool { status == .connected }

    func setAlbumArt(_ data: Data?) {
        guard data != albumArtData else { return }
        albumArtData = data
        albumArt = data.flatMap(NSImage.init(data:))
    }

    public var hasNowPlaying: Bool {
        !(nowPlayingTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var activeTransferCount: Int {
        transfers.filter { $0.status == .transferring }.count
    }

    /// One-line status used under the device name in lists.
    public var statusLine: String {
        switch status {
        case .connected:
            var parts = ["Connected"]
            if let batteryPercent { parts.append("\(batteryPercent)%") }
            return parts.joined(separator: " · ")
        case .available:
            return isAwaitingPairing ? "Waiting for phone…" : "Ready to pair"
        case .offline:
            if let lastSeen {
                return "Last seen \(lastSeen.formatted(.relative(presentation: .named)))"
            }
            return "Not nearby"
        }
    }

    // Actions
    public func ping() { onPing?() }
    func shareClipboardText(_ text: String) -> Bool { onShareClipboardText?(text) ?? false }
    public func sendClipboard() { onSendClipboard?() }
    public func sendFiles(_ urls: [URL]) { onSendFiles?(urls) }
    public func findMyPhone() { onFindPhone?() }
    public func lockDevice() { onLockDevice?() }
    public func pair() {
        isAwaitingPairing = true
        onPair?()
    }
    public func unpair() { onUnpair?() }
    public func executeCommand(id: String) { onExecuteCommand?(id) }
    public func saveCommand(_ command: RemoteCommand) { onSaveCommand?(command) }
    public func deleteCommand(id: String) { onDeleteCommand?(id) }
    public func sendSMS(to addresses: [String], message: String, threadId: Int64?, subId: Int64? = nil) {
        onSendSMS?(addresses, message, threadId, subId)
    }

    /// The SIM to offer for a conversation: the one it last used, else the one
    /// the latest sent message went out on, else the first.
    func defaultSIM(for thread: SMSConversation?) -> Int64? {
        let ids = Set(sims.map(\.id))
        if let used = thread?.messages.last(where: { $0.subId.map(ids.contains) ?? false })?.subId {
            return used
        }
        let lastSent = smsThreads
            .flatMap(\.messages)
            .filter { $0.isOutgoing && ($0.subId.map(ids.contains) ?? false) }
            .max { $0.date < $1.date }
        return lastSent?.subId ?? sims.first?.id
    }
    /// The thread's people by name where the phone's contacts know them.
    func title(for thread: SMSConversation) -> String {
        guard !thread.addresses.isEmpty else { return thread.title }
        return thread.addresses.map { contacts.contact(for: $0)?.name ?? $0 }.joined(separator: ", ")
    }

    /// The contact photo for a one-to-one thread.
    func photo(for thread: SMSConversation) -> Data? {
        guard thread.addresses.count == 1, let address = thread.addresses.first else { return nil }
        return contacts.contact(for: address)?.photo
    }

    public func refreshMessages() { onRefreshMessages?() }
    public func refreshContacts() { onRefreshContacts?() }
    public func refreshPhotos() { onRefreshPhotos?() }
    public func startMessage(to number: String, name: String? = nil) {
        draftRecipient = (number, name)
        onStartMessageToContact?(number, name)
    }
    public func openThread(_ threadId: Int64) { onOpenThread?(threadId) }
    public func loadEarlierMessages(_ threadId: Int64) { onLoadEarlierMessages?(threadId) }
    public func setVolume(_ val: Float) { onSetVolume?(val) }
    public func playPauseMedia() { onMediaAction?("PlayPause") }
    public func nextMedia() { onMediaAction?("Next") }
    public func previousMedia() { onMediaAction?("Previous") }
    public func reply(to notification: PhoneNotification, text: String) { onReplyToNotification?(notification, text) }
    public func dismiss(_ notification: PhoneNotification) { onDismissNotification?(notification) }
}

#if DEBUG
// MARK: - Sample devices for previews and marketing captures

enum DemoDevices {
    static let phone = "Pixel 10"
    static let tablet = "Samsung Galaxy Tab S10+"
    static let nearby = "Samsung Galaxy S25"
    static let offline = "Fairphone 5"
}

extension DeviceViewModel {
    public static func mockConnectedPhone() -> DeviceViewModel {
        let now = Date()
        let anwar = "+1 202 555 0146"
        let theo = "+1 202 555 0162"
        let leila = "+1 202 555 0118"
        let arcadeWalk = SMSConversation(threadId: 101, addresses: [anwar], messages: [
            SMSMessage(body: "The copper arcade catches the light around five. Want to start there?", addresses: [anwar], date: now.addingTimeInterval(-3360), type: 1, threadId: 101, read: true),
            SMSMessage(body: "Yes! I’ll bring the wide lens. Which entrance?", addresses: [anwar], date: now.addingTimeInterval(-2800), type: 2, threadId: 101, read: true),
            SMSMessage(body: "The one across from the tile workshop.", addresses: [anwar], date: now.addingTimeInterval(-420), type: 1, threadId: 101, read: true),
            SMSMessage(body: "Found it. See you under the arch!", addresses: [anwar], date: now.addingTimeInterval(-95), type: 2, threadId: 101, read: true)
        ])
        let route = SMSConversation(threadId: 102, addresses: [theo], messages: [
            SMSMessage(body: "I marked the footbridge on the route map. It’s a good spot for a panorama.", addresses: [theo], date: now.addingTimeInterval(-5100), type: 1, threadId: 102, read: true)
        ])
        let prints = SMSConversation(threadId: 103, addresses: [leila], messages: [
            SMSMessage(body: "The courtyard prints are dry. Pick them up at the studio tomorrow?", addresses: [leila], date: now.addingTimeInterval(-9000), type: 1, threadId: 103, read: true)
        ])

        var mockBook = ContactBook()
        let contacts = [
            Contact(id: "c1", name: "Anwarul Islam", numbers: [anwar, "+1 202 555 0147"], emails: ["hi@anwar.bd"]),
            Contact(id: "c2", name: "Theo Park", numbers: [theo], emails: ["theo@example.org"]),
            Contact(id: "c3", name: "Leila Noor", numbers: [leila], emails: ["leila@example.org"]),
            Contact(id: "c4", name: "Robin Ellis", numbers: ["+1 202 555 0175"]),
            Contact(id: "c5", name: "Inez Costa", numbers: ["+1 202 555 0139"], emails: ["inez@example.org"])
        ]
        for contact in contacts { mockBook.set(contact, for: contact.id) }

        let phone = DeviceViewModel(
            id: "mock_phone",
            name: DemoDevices.phone,
            deviceType: .phone,
            status: .connected,
            batteryPercent: 68,
            isCharging: false,
            networkType: "5G",
            cellularSignalStrength: 4,
            volume: 0.42,
            nowPlayingTitle: "Window Seat",
            nowPlayingArtist: "June Atlas",
            nowPlayingAlbum: "The Long Way Home",
            nowPlayingIsPlaying: true,
            transfers: [
                TransferItem(deviceId: "mock_phone", deviceName: DemoDevices.phone, filename: "Copper arcade.jpg", totalBytes: 4_000_000, transferredBytes: 1_480_000, direction: .incoming, status: .transferring, progress: 0.37),
                TransferItem(deviceId: "mock_phone", deviceName: DemoDevices.phone, filename: "Walking route.pdf", totalBytes: 384_000, transferredBytes: 384_000, direction: .outgoing, status: .completed, progress: 1, timestamp: now.addingTimeInterval(-1260)),
                TransferItem(deviceId: "mock_phone", deviceName: DemoDevices.phone, filename: "Courtyard contact sheet.pdf", totalBytes: 1_680_000, transferredBytes: 1_680_000, direction: .incoming, status: .completed, progress: 1, timestamp: now.addingTimeInterval(-2520))
            ],
            smsThreads: [arcadeWalk, route, prints],
            commands: [
                RemoteCommand(id: "demo_open_photos", name: "Open Photos", command: "open -a Photos"),
                RemoteCommand(id: "demo_open_map", name: "Open the route map", command: "open ~/Documents/Walking\\ route.pdf"),
                RemoteCommand(id: "demo_show_prints", name: "Show contact sheets", command: "open ~/Pictures/Prints")
            ],
            notifications: [
                PhoneNotification(id: "n0", deviceId: "mock_phone", appName: "Messages", title: "Lantern Print Lab", text: "Use 482615 to sign in to Lantern Print Lab.", date: now.addingTimeInterval(-48), replyId: nil, isDismissable: true, code: "482615"),
                PhoneNotification(id: "n1", deviceId: "mock_phone", appName: "Signal", title: "Anwarul Islam", text: "The library steps are empty. One more stop?", date: now.addingTimeInterval(-190), replyId: "r1", isDismissable: true),
                PhoneNotification(id: "n2", deviceId: "mock_phone", appName: "Calendar", title: "Contact sheet review", text: "Tomorrow at 10 at the Lantern studio.", date: now.addingTimeInterval(-1260), replyId: nil, isDismissable: true)
            ]
        )
        phone.onRemoteInput = { _ in true }
        phone.contacts = mockBook
        phone.calls = [
            CallEntry(date: now.addingTimeInterval(-540), kind: .missed, number: anwar),
            CallEntry(date: now.addingTimeInterval(-2400), kind: .outgoing, number: leila),
            CallEntry(date: now.addingTimeInterval(-6300), kind: .answered, number: theo)
        ]
        let gallery = [
            ("Copper arcade", "Arcade Details"), ("Library steps", "Field Notes"),
            ("Glass atrium", "Field Notes"), ("Courtyard arch", "Courtyard Studies"),
            ("North stair", "Courtyard Studies"), ("Depot clock", "Field Notes"),
            ("Tile workshop", "Arcade Details"), ("River bridge", "Field Notes"),
            ("Lantern passage", "Arcade Details")
        ]
        phone.photos = gallery.enumerated().compactMap { index, item in
            let (title, folder) = item
            guard let url = Bundle.main.url(forResource: "PreviewPhoto-" + title, withExtension: "jpg") else { return nil }
            let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            return PhonePhoto(id: "demo-" + title, name: title + ".jpg", relativePath: folder + "/" + title + ".jpg",
                              fullPath: url.path, fileSize: Int64(size ?? 0),
                              modifiedDate: now.addingTimeInterval(Double(-index * 3600)), folder: folder)
        }
        phone.timeline = PlaybackTimeline(length: 217_000, position: 89_000, reportedAt: .now, canSeek: true)
        phone.onSeek = { [weak phone] position in
            phone?.timeline.position = position
            phone?.timeline.reportedAt = .now
        }
        phone.onSetVolume = { [weak phone] in phone?.volume = $0 }
        phone.canSetVolume = true
        phone.lanAddress = "192.0.2.46"
        phone.bluetoothAddress = "02-00-00-00-00-46"
        phone.sims = [PhoneSIM(id: 1, number: 1, networkType: "5G"), PhoneSIM(id: 2, number: 2, networkType: "4G")]
        return phone
    }

    public static func mockConnectedTablet() -> DeviceViewModel {
        DeviceViewModel(id: "mock_tablet", name: DemoDevices.tablet, deviceType: .tablet, status: .connected, batteryPercent: 91, networkType: "Wi-Fi")
    }

    public static func mockAvailablePhone() -> DeviceViewModel {
        DeviceViewModel(id: "mock_available", name: DemoDevices.nearby, deviceType: .phone, status: .available)
    }

    public static func mockOfflinePhone() -> DeviceViewModel {
        DeviceViewModel(id: "mock_offline", name: DemoDevices.offline, deviceType: .phone, status: .offline, lastSeen: Date().addingTimeInterval(-3600 * 5))
    }
}
#endif
