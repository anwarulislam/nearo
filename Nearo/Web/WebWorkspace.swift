import AppKit
import UserNotifications
import ImageIO
import UniformTypeIdentifiers

struct WebAction: Decodable {
    let name: String
    var device: String?
    var id: String?
    var text: String?
    var value: String?
    var sim: String?
    var addresses: [String]?
}

/// The browser keeps its own selection. Device operations go through the same view models as SwiftUI.
@MainActor
struct WebWorkspace {
    typealias Object = [String: Any]
    let model: NearoAppModel
    let domainAddress: URL
    let ipAddress: URL
    private var drives: PhoneFilesController { .shared }
    private var missing: WebFailure { WebFailure("This item is no longer available. Refresh and try again.") }

    func state(_ query: [String: String]) throws -> WebResponse {
        let devices = model.allDevices
        var result: Object = ["devices": devices.map(summary), "selected": model.selectedDeviceId ?? "",
                              "appearance": UserDefaults.standard.string(forKey: "workspaceAppearance") ?? "system"]
        let theme = WorkspaceTheme.saved
        result["theme"] = theme.rawValue
        result["themeColors"] = theme.webColors
        let page = query["page"] ?? "Overview"
        if let pair = model.incomingPairRequest {
            result["request"] = ["id": pair.id, "name": pair.deviceName, "code": pair.verificationCode ?? "",
                                 "fingerprint": pair.fingerprint ?? ""]
        }
        if page == "Settings" {
            result["settings"] = settings()
            result["themeOptions"] = WorkspaceTheme.allCases.map(\.rawValue)
            result["themePalettes"] = Dictionary(uniqueKeysWithValues: WorkspaceTheme.allCases.map { ($0.rawValue, $0.webColors) })
        }
        if let device = devices.first(where: { $0.id == query["device"] }) ?? model.selectedDevice ?? devices.first {
            result["device"] = device.id
            result["detail"] = detail(device, page: page, thread: query["thread"])
        }
        return WebResponse(try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]))
    }

    private func summary(_ d: DeviceViewModel) -> Object {
        ["id": d.id, "name": d.name, "type": d.deviceType.rawValue, "status": d.status.rawValue, "online": d.isConnected,
         "statusLine": d.statusLine, "battery": d.batteryPercent as Any, "charging": d.isCharging, "network": d.networkType ?? "",
         "connection": d.isViaBluetooth ? "Bluetooth" : d.isViaTailscale ? "Tailscale" : "Wi-Fi", "canLock": d.canLock,
         "canSyncCalls": d.status != .available && d.onSyncCalls != nil,
         "calls": d.status == .available ? 0 : d.calls.count, "contacts": d.contacts.count, "photos": d.photos.count, "commands": d.commands.count, "notifications": d.notifications.count,
         "awaiting": d.isAwaitingPairing, "pairCode": d.pairingVerificationCode ?? ""]
    }

    private func detail(_ d: DeviceViewModel, page: String, thread: String?) -> Object {
        var info = Object()
        if page == "Files" || page == "Overview" {
            switch drives.driveState(for: d.id) {
            case .mounted: info["drive"] = "Mounted"
            case .mounting: info["drive"] = "Mounting"
            case .notConnected: info["drive"] = "Not connected"
            case .turnedOff: info["drive"] = "Turned off"
            case .ejected: info["drive"] = "Ejected"
            case .failed(let reason): info["drive"] = "Failed"; info["driveError"] = reason
            }
        }
        if page == "Contacts" || page == "Messages" {
            let names = UserDefaults.standard.string(forKey: SIMNames.key) ?? ""
            info["sims"] = d.sims.map { ["id": String($0.id), "name": SIMNames.label(for: $0, deviceId: d.id, in: names)] }
        }
        switch page {
        case "Overview":
            if d.isConnected, d.deviceType == .phone {
                d.handset.refreshIfNeeded()
                info["phoneTime"] = d.handset.time(at: .now)
                info["clockDescription"] = d.handset.clockDescription
                info["handsetHelp"] = d.handset.helpText
                info["wallpaper"] = d.handset.version
            }
            info["notices"] = d.notifications.prefix(3).map(notice)
            info["threads"] = d.smsThreads.prefix(1).map { threadInfo($0, d) }
            info["media"] = ["title": d.nowPlayingTitle ?? "", "artist": d.nowPlayingArtist ?? "", "album": d.nowPlayingAlbum ?? "",
                             "playing": d.nowPlayingIsPlaying, "volume": d.volume, "canSetVolume": d.canSetVolume] as Object
        case "Messages":
            info["threads"] = d.smsThreads.map { threadInfo($0, d) }
            let conversation = d.smsThreads.first { String($0.id) == thread } ?? d.smsThreads.first
            if let conversation {
                info["thread"] = String(conversation.id)
                info["messages"] = conversation.messages.sorted { $0.date < $1.date }.map {
                    ["text": $0.body, "out": $0.isOutgoing, "date": $0.date.timeIntervalSince1970, "attachments": $0.attachments.count] as Object
                }
                info["defaultSIM"] = d.defaultSIM(for: conversation).map(String.init)
            }
        case "Calls" where d.status != .available:
            info["syncMessage"] = d.callSyncMessage ?? ""
            info["syncing"] = d.isSyncingCalls
            info["needsSync"] = d.onSyncCalls != nil && !d.isSyncingCalls && d.callSyncMessage == nil
            info["calls"] = d.calls.map { call in
                ["caller": call.caller(in: d.contacts), "number": call.number ?? "", "kind": call.kind.label,
                 "date": call.date.timeIntervalSince1970] as Object
            }
        case "Contacts": info["contacts"] = d.contacts.allContacts.map {
            ["id": $0.id, "name": $0.name, "numbers": $0.numbers, "emails": $0.emails, "photo": $0.photo != nil] as Object
        }
        case "Photos":
            info["loading"] = d.isLoadingPhotos
            info["photos"] = d.photos.map { ["id": $0.id, "name": $0.name, "album": $0.folder, "size": $0.formattedSize,
                                             "modified": $0.modifiedDate.timeIntervalSince1970] as Object }
        case "Notifications": info["notices"] = d.notifications.map(notice)
        case "Files": info["transfers"] = d.transfers.map { item -> Object in
            let status: String
            switch item.status {
            case .queued: status = "Queued"
            case .transferring: status = "\(Int(item.progress * 100))%"
            case .completed: status = "Completed"
            case .cancelled: status = "Cancelled"
            case .failed(let reason): status = reason
            }
            return ["id": item.id.uuidString, "name": item.filename, "status": status, "direction": item.direction.rawValue,
                    "size": ByteCountFormatter.string(fromByteCount: item.totalBytes, countStyle: .file),
                    "reveal": item.localURL != nil && item.status == .completed]
        }
        case "Commands":
            info["commands"] = d.commands.map { ["id": $0.id, "name": $0.name, "code": $0.command] }
            info["shortcuts"] = UserDefaults.standard.bool(forKey: RunCommandPlugin.shortcutsKey)
        default: break
        }
        return info
    }

    private func threadInfo(_ thread: SMSConversation, _ d: DeviceViewModel) -> Object {
        ["id": String(thread.id), "name": d.title(for: thread), "addresses": thread.addresses, "snippet": thread.snippet,
         "date": thread.lastMessage?.date.timeIntervalSince1970 ?? 0, "unread": thread.unreadCount]
    }

    private func notice(_ item: PhoneNotification) -> Object {
        ["id": item.id, "app": item.appName, "title": item.title, "body": item.text, "date": item.date.timeIntervalSince1970,
         "reply": item.replyId != nil, "dismiss": item.isDismissable, "code": item.code ?? "", "image": item.imageData != nil]
    }

    private func settings() -> Object {
        let s = model.settingsModel
        let prefs = UserDefaults.standard
        let network: String
        switch s.tailscaleStatus {
        case .notInstalled: network = "Not installed"
        case .notRunning: network = "Not connected"
        case .running(let ip, let phones): network = ([ip] + phones.map(\.name)).joined(separator: " · ")
        }
        return ["webDomain": domainAddress.absoluteString, "webIP": ipAddress.absoluteString,
                "mac": s.deviceName, "identity": s.deviceId, "fingerprint": s.certificateFingerprint, "port": s.listeningPort,
                "version": NearoCredits.version, "login": s.launchAtLogin, "reduceMotion": prefs.bool(forKey: MotionPreference.key),
                "copyCodes": prefs.bool(forKey: OneTimeCode.autoCopyKey), "pauseCalls": prefs.object(forKey: CallMediaPauser.settingKey) as? Bool ?? true,
                "callCard": prefs.object(forKey: CallCard.settingKey) as? Bool ?? true, "awayLock": prefs.bool(forKey: AwayLock.settingKey),
                "bluetooth": s.isBluetoothEnabled, "bluetoothStatus": s.bluetoothStatusText, "tailscale": s.isTailscaleDiscoveryEnabled,
                "tailscaleStatus": network, "mount": drives.isEnabled, "accessibility": s.isAccessibilityTrusted,
                "notifications": s.notificationAuthStatus == .authorized || s.notificationAuthStatus == .provisional,
                "autoUpdate": UpdateController.shared.checksAutomatically,
                "paired": s.pairedDevices.map { d -> Object in
                    ["id": d.id, "name": d.deviceName, "clipboard": d.isClipboardSyncEnabled, "notifications": d.isNotificationSyncEnabled,
                     "paired": d.pairedDate.timeIntervalSince1970, "method": drives.method(for: d.id).rawValue,
                     "adb": drives.adbAddress(for: d.id), "driveError": drives.mountError[d.id] ?? drives.adbProblem[d.id] ?? ""]
                }]
    }

    func image(_ query: [String: String]) async throws -> WebResponse {
        guard let d = model.allDevices.first(where: { $0.id == query["device"] }), let id = query["id"] else { throw missing }
        switch query["kind"] {
        case "wallpaper":
            guard d.isConnected, let jpeg = d.handset.jpeg else { throw missing }
            return WebResponse(jpeg, mime: "image/jpeg")
        case "contact", "notice":
            let data = query["kind"] == "contact" ? d.contacts.contacts[id]?.photo : d.notifications.first { $0.id == id }?.imageData
            guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceThumbnailMaxPixelSize: 96] as CFDictionary),
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw missing }
            return WebResponse(png, mime: "image/png")
        default:
            guard let photo = d.photos.first(where: { $0.id == id }) else { throw missing }
            if query["kind"] == "preview" {
                let jpeg = await Task.detached(priority: .userInitiated) { () -> Data? in
                    guard let src = CGImageSourceCreateWithURL(photo.url as CFURL, nil),
                          let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                              kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1920] as CFDictionary) else { return nil }
                    return NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: 0.88])
                }.value
                guard let jpeg else { throw WebFailure("Connect the phone drive to preview this photo.") }
                return WebResponse(jpeg, mime: "image/jpeg")
            }
            guard let image = await PhotoThumbnailService.shared.thumbnail(for: photo, deviceId: d.id),
                  let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                  let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { throw missing }
            return WebResponse(jpeg, mime: "image/jpeg")
        }
    }

    func perform(_ a: WebAction, isServing: () -> Bool) async throws {
        let text = a.text ?? "", id = a.id ?? ""
        switch a.name {
        case "discover": model.refreshDiscovery(); return
        case "connect":
            guard !text.isEmpty, await model.addManualPeer(address: text) else { throw WebFailure("Couldn’t connect to this address.") }
            return
        case "acceptPair", "declinePair":
            guard let r = model.incomingPairRequest, r.id == id, (r.fingerprint ?? "") == a.value,
                  (r.verificationCode ?? "") == text else { throw missing }
            if a.name == "acceptPair" { model.acceptIncomingPairRequest(r) } else { model.rejectIncomingPairRequest() }
            return
        case "setting": try setPreference(a); return
        default: break
        }
        guard let d = model.allDevices.first(where: { $0.id == a.device }) else { throw missing }
        if a.name == "downloads" {
            NSWorkspace.shared.open(ReceiveFolder.url(for: d.id))
            return
        }
        if a.name == "pair", d.status == .available { d.pair(); return }
        if a.name == "unpair", d.status != .available { d.unpair(); return }
        if ["syncCalls", "loadCalls"].contains(a.name), d.status != .available, let sync = d.onSyncCalls {
            sync(a.name == "loadCalls")
            return
        }
        if a.name == "savePhoto", let photo = d.photos.first(where: { $0.id == id }) {
            try await PhotoDownloads.shared.save(photo); return
        }
        guard d.isConnected else { throw WebFailure("This device is offline.") }
        switch a.name {
        case "ring": d.findMyPhone()
        case "ping": d.ping()
        case "lock" where d.canLock: d.lockDevice()
        case "clipboard":
            guard !text.isEmpty, d.shareClipboardText(text) else { throw WebFailure("Enable clipboard sharing for this device.") }
        case "sendFiles":
            NSApp.activate()
            let panel = FilePicker.sendPanel(for: d.name)
            guard await panel.begin() == .OK, !panel.urls.isEmpty else { throw WebFailure("File selection cancelled.") }
            guard isServing(), d.isConnected else { throw WebFailure("The browser session or device connection ended.") }
            d.sendFiles(panel.urls)
        case "refreshContacts": d.refreshContacts()
        case "refreshMessages": d.refreshMessages()
        case "refreshPhotos": d.refreshPhotos()
        case "openThread", "earlier":
            guard let thread = d.smsThreads.first(where: { String($0.id) == id }) else { throw missing }
            if a.name == "earlier" { d.loadEarlierMessages(thread.id) } else { d.openThread(thread.id) }
        case "sms":
            let thread = d.smsThreads.first { String($0.id) == id }
            guard id.isEmpty || thread != nil else { throw missing }
            let recipients = thread?.addresses ?? a.addresses ?? []
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !recipients.isEmpty,
                  recipients.allSatisfy({ !$0.isEmpty }), recipients.count <= 100 else { throw WebFailure("Enter a recipient and a message.") }
            let sim = a.sim.flatMap(Int64.init)
            guard sim == nil || d.sims.contains(where: { $0.id == sim }) else { throw missing }
            d.sendSMS(to: recipients, message: text, threadId: thread?.id, subId: sim)
        case "dismiss", "reply":
            guard let item = d.notifications.first(where: { $0.id == id }) else { throw missing }
            if a.name == "reply", item.replyId != nil, !text.isEmpty { d.reply(to: item, text: text) }
            else if a.name == "dismiss", item.isDismissable { d.dismiss(item) }
            else { throw missing }
        case "clear": for n in d.notifications where n.isDismissable { d.dismiss(n) }
        case "mount":
            if !drives.isEnabled { drives.isEnabled = true } else { drives.mountAgain(d.id) }
        case "finder", "eject":
            guard drives.mountedDevices.contains(d.id) else { throw missing }
            if a.name == "eject" { drives.eject(d.id) } else { drives.showInFinder(d.id) }
        case "reveal":
            guard let url = d.transfers.first(where: { $0.id.uuidString == id && $0.status == .completed })?.localURL else { throw missing }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case "run", "deleteCommand", "duplicateCommand":
            guard let command = d.commands.first(where: { $0.id == id }) else { throw missing }
            if a.name == "run" { d.executeCommand(id: id) }
            else if a.name == "deleteCommand" { d.deleteCommand(id: id) }
            else { d.saveCommand(RemoteCommand(name: command.name + " copy", command: command.command)) }
        case "saveCommand":
            guard let code = a.value, !code.isEmpty, !text.isEmpty, id.isEmpty || d.commands.contains(where: { $0.id == id }) else { throw missing }
            d.saveCommand(RemoteCommand(id: id.isEmpty ? UUID().uuidString : id, name: text, command: code))
        case "playPause": d.playPauseMedia()
        case "next": d.nextMedia()
        case "previous": d.previousMedia()
        case "volume":
            guard d.canSetVolume, let level = Float(text), (0...1).contains(level) else { throw missing }
            d.setVolume(level)
        default: throw WebFailure("Action unavailable.")
        }
    }

    private func setPreference(_ a: WebAction) throws {
        let prefs = UserDefaults.standard, s = model.settingsModel, on = a.value == "true"
        switch a.id {
        case "mac": if let text = a.text, !text.isEmpty { s.saveDeviceName(text) }
        case "appearance":
            guard let value = a.value, WorkspaceAppearance(rawValue: value) != nil else { throw missing }
            prefs.set(value, forKey: "workspaceAppearance")
        case "theme":
            guard let value = a.value, let theme = WorkspaceTheme(rawValue: value) else { throw missing }
            prefs.set(theme.rawValue, forKey: WorkspaceTheme.key)
        case "login": s.setLaunchAtLogin(on)
        case "reduceMotion": prefs.set(on, forKey: MotionPreference.key)
        case "copyCodes": prefs.set(on, forKey: OneTimeCode.autoCopyKey)
        case "pauseCalls": prefs.set(on, forKey: CallMediaPauser.settingKey)
        case "callCard": prefs.set(on, forKey: CallCard.settingKey)
        case "awayLock": prefs.set(on, forKey: AwayLock.settingKey)
        case "bluetooth": s.isBluetoothEnabled = on
        case "tailscale": s.isTailscaleDiscoveryEnabled = on
        case "mount": drives.isEnabled = on
        case "shortcuts":
            prefs.set(on, forKey: RunCommandPlugin.shortcutsKey)
            NearoService.shared.runCommandPlugin.refreshShortcuts()
        case "autoUpdate": UpdateController.shared.checksAutomatically = on
        case "checkUpdate": UpdateController.shared.checkForUpdates()
        case "notificationsPermission":
            if s.notificationAuthStatus == .notDetermined { s.requestNotificationPermission() } else { s.openNotificationSettings() }
        case "accessibilityPermission": s.promptAccessibility()
        case "pointer": PresenterOverlayWindowController.shared.update(xPos: 0.5, yPos: 0.5)
        case "deviceClipboard", "deviceNotifications", "method", "adb":
            guard let d = s.pairedDevices.first(where: { $0.id == a.device }) else { throw missing }
            if a.id == "method", let method = PhoneFilesMethod(rawValue: a.value ?? "") { drives.setMethod(method, for: d.id) }
            else if a.id == "adb" { drives.setADBAddress(a.text ?? "", for: d.id) }
            else if a.id == "deviceClipboard" || a.id == "deviceNotifications" {
                s.setSync(deviceId: d.id, clipboard: a.id == "deviceClipboard" ? on : d.isClipboardSyncEnabled,
                          notifications: a.id == "deviceNotifications" ? on : d.isNotificationSyncEnabled)
            } else { throw missing }
        default: throw WebFailure("Unknown setting.")
        }
    }
}
