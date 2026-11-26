import AppKit
import CryptoKit
import ImageIO
import Observation
import UniformTypeIdentifiers

nonisolated struct HandsetClock {
    let adjustment: TimeInterval
    let zone: TimeZone
    let uses24Hours: Bool?

    init?(sample: String, received: Date) {
        let lines = sample.components(separatedBy: .newlines)
        guard lines.count >= 3 else { return nil }
        let stamp = lines[0].split(separator: " ")
        guard stamp.count == 2, let seconds = Int64(stamp[0]),
              let sign = stamp[1].first, "+-".contains(sign), stamp[1].count == 5,
              let hours = Int(stamp[1].dropFirst().prefix(2)), let minutes = Int(stamp[1].suffix(2)),
              hours <= 18, minutes < 60,
              let offset = TimeZone(secondsFromGMT: (sign == "-" ? -1 : 1) * (hours * 3600 + minutes * 60)) else { return nil }
        adjustment = TimeInterval(seconds) - received.timeIntervalSince1970
        zone = TimeZone(identifier: lines[1]) ?? offset
        uses24Hours = lines[2] == "24" ? true : (lines[2] == "12" ? false : nil)
    }
}

/// Shared by the SwiftUI and browser overviews. Only the small wallpaper thumbnail persists.
@MainActor @Observable
final class HandsetPreview {
    private let deviceID: String
    private let cache: URL
    private(set) var clock: HandsetClock?
    private(set) var wallpaper: NSImage?
    private(set) var jpeg: Data?
    private(set) var version = ""
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var lastRead = Date.distantPast
    @ObservationIgnored private var lastAddress: String?
    @ObservationIgnored private var lastMount: URL?
    @ObservationIgnored private var loaded = false

    init(deviceID: String, cacheDirectory: URL = URL.cachesDirectory.appending(path: "Nearo/Handsets")) {
        self.deviceID = deviceID
        let key = SHA256.hash(data: Data(deviceID.utf8)).map { String(format: "%02x", $0) }.joined()
        cache = cacheDirectory.appendingPathComponent(key + ".jpg")
    }

    func time(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = clock?.zone ?? .autoupdatingCurrent
        let localeHour = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .autoupdatingCurrent) ?? "H"
        let use24 = clock?.uses24Hours ?? (localeHour.contains("H") || localeHour.contains("k"))
        formatter.dateFormat = use24 ? "HH:mm" : "h:mm"
        return formatter.string(from: date.addingTimeInterval(clock?.adjustment ?? 0))
    }

    var clockDescription: String { clock == nil ? "Local time on this Mac" : "Phone time" }

    var helpText: String {
        if wallpaper != nil { return clockDescription }
        return clockDescription + ". To share a wallpaper, save a copy as Pictures/Nearo/wallpaper.jpg or wallpaper.png on the phone’s mounted drive."
    }

    func refreshIfNeeded() {
        let drives = PhoneFilesController.shared
        let mount = drives.mountedURL(for: deviceID)
        let address = drives.method(for: deviceID) == .adb ? drives.adbAddress(for: deviceID) : nil
        refreshIfNeeded(mount: mount, address: address)
    }

    func refreshIfNeeded(mount: URL?, address: String?) {
        let changed = mount != lastMount || address != lastAddress
        guard changed || (task == nil && Date.now.timeIntervalSince(lastRead) >= 300) else { return }
        task?.cancel()
        if lastAddress != address { clock = nil }
        lastAddress = address
        lastMount = mount
        lastRead = .now
        task = Task {
            guard !Task.isCancelled else { return }
            if !loaded {
                if let data = try? Data(contentsOf: cache) { apply(data) }
                loaded = true
            }
            let adb = address.flatMap { $0.contains(":") ? ADBTransport(address: $0) : nil }
            let sample = try? await adb?.handsetClock()
            guard !Task.isCancelled else { return }
            clock = sample
            let original = try? await adb?.handsetWallpaper()
            guard !Task.isCancelled else { return }
            let thumbnail = await Task.detached(priority: .utility) { () -> Data? in
                if let original, let jpeg = Self.thumbnail(original) { return jpeg }
                return mount.flatMap(Self.sharedWallpaper)
            }.value
            guard !Task.isCancelled else { return }
            if let thumbnail, thumbnail != jpeg {
                apply(thumbnail)
                try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? thumbnail.write(to: cache, options: .atomic)
            }
            task = nil
        }
    }

    func forget() {
        task?.cancel()
        task = nil
        clock = nil
        wallpaper = nil
        jpeg = nil
        version = ""
        lastRead = .distantPast
        loaded = false
        try? FileManager.default.removeItem(at: cache)
    }

    private func apply(_ data: Data) {
        guard let image = NSImage(data: data) else { return }
        jpeg = data
        wallpaper = image
        version = UUID().uuidString
    }

    // KDE Connect exposes shared storage. A user can put a copy here when Android
    // keeps the system wallpaper private. Only inspect these named files.
    private nonisolated static func sharedWallpaper(_ mount: URL) -> Data? {
        let root = mount.resolvingSymlinksInPath()
        for ext in ["jpg", "png"] {
            let url = root.appending(path: "Pictures/Nearo/wallpaper." + ext).resolvingSymlinksInPath()
            guard url.path.hasPrefix(root.path + "/"),
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true, let size = values.fileSize, size > 0, size <= 12 * 1024 * 1024,
                  let data = try? Data(contentsOf: url), let jpeg = thumbnail(data) else { continue }
            return jpeg
        }
        return nil
    }

    nonisolated static func thumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 384
              ] as CFDictionary) else { return nil }
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(result, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? result as Data : nil
    }
}
