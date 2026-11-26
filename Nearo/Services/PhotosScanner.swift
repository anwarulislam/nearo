//
//  PhotosScanner.swift
//  Nearo
//
//  Scans the mounted phone filesystem for photos, indexes them, and caches
//  metadata to disk for instant subsequent loads.
//

import Foundation

nonisolated public final class PhotosScanner: Sendable {
    public static let shared = PhotosScanner()

    public static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "webp", "gif", "bmp", "tiff", "tif"
    ]

    private init() {}

    private func indexCacheURL(for deviceId: String) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("Nearo/PhotosIndex", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("\(deviceId).json")
    }

    /// Load previously cached photo list from disk (loads in ~1ms).
    public func loadCachedPhotos(for deviceId: String) -> [PhonePhoto]? {
        let file = indexCacheURL(for: deviceId)
        guard let data = try? Data(contentsOf: file),
              let list = try? JSONDecoder().decode([PhonePhoto].self, from: data) else {
            return nil
        }
        return list
    }

    /// Save photo list to disk cache.
    public func saveCachedPhotos(_ photos: [PhonePhoto], for deviceId: String) {
        let file = indexCacheURL(for: deviceId)
        guard let data = try? JSONEncoder().encode(photos) else { return }
        try? data.write(to: file, options: .atomic)
    }

    /// Find the mount directory for a device on this Mac.
    public func mountURL(for deviceId: String, deviceName: String) -> URL? {
        let sanitized = deviceName.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
        let primary = PhoneMount.mountsDirectory.appendingPathComponent(sanitized, isDirectory: true)
        if FileManager.default.fileExists(atPath: primary.path) {
            return primary
        }
        // Check if any directory in mountsDirectory matches or exists
        if let contents = try? FileManager.default.contentsOfDirectory(at: PhoneMount.mountsDirectory, includingPropertiesForKeys: nil) {
            for dir in contents where dir.lastPathComponent.localizedCaseInsensitiveContains(sanitized) || sanitized.localizedCaseInsensitiveContains(dir.lastPathComponent) {
                return dir
            }
            if let first = contents.first {
                return first
            }
        }
        return nil
    }

    /// Scan the mounted phone for photos, prioritizing DCIM/Camera, Pictures, and Download.
    public func scan(
        mountURL: URL,
        onBatch: (@Sendable ([PhonePhoto]) -> Void)? = nil
    ) async -> [PhonePhoto] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var found: [PhonePhoto] = []
                var seenPaths = Set<String>()

                let subdirs = [
                    (folder: "Camera", rel: "DCIM/Camera"),
                    (folder: "DCIM", rel: "DCIM"),
                    (folder: "Pictures", rel: "Pictures"),
                    (folder: "Download", rel: "Download")
                ]

                let keys: [URLResourceKey] = [.nameKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey]

                for target in subdirs {
                    let folderURL = mountURL.appendingPathComponent(target.rel)
                    guard FileManager.default.fileExists(atPath: folderURL.path) else { continue }

                    guard let enumerator = FileManager.default.enumerator(
                        at: folderURL,
                        includingPropertiesForKeys: keys,
                        options: [.skipsHiddenFiles]
                    ) else { continue }

                    var batch: [PhonePhoto] = []

                    for case let fileURL as URL in enumerator {
                        if Task.isCancelled { break }
                        guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                              values.isDirectory != true else { continue }

                        let ext = fileURL.pathExtension.lowercased()
                        guard Self.supportedExtensions.contains(ext) else { continue }

                        let path = fileURL.path
                        guard !seenPaths.contains(path) else { continue }
                        seenPaths.insert(path)

                        let name = values.name ?? fileURL.lastPathComponent
                        let relPath = fileURL.path.replacingOccurrences(of: mountURL.path + "/", with: "")
                        let size = Int64(values.fileSize ?? 0)
                        let date = values.contentModificationDate ?? .distantPast

                        // Identify friendly folder name (e.g. Screenshots, Camera, WhatsApp)
                        let parentFolder = fileURL.deletingLastPathComponent().lastPathComponent
                        let folderName = (parentFolder.lowercased() == "camera" || parentFolder.lowercased() == "dcim")
                            ? "Camera"
                            : parentFolder

                        let photo = PhonePhoto(
                            id: relPath,
                            name: name,
                            relativePath: relPath,
                            fullPath: path,
                            fileSize: size,
                            modifiedDate: date,
                            folder: folderName
                        )

                        batch.append(photo)

                        if batch.count >= 60 {
                            found.append(contentsOf: batch)
                            let currentBatch = batch
                            batch.removeAll()
                            onBatch?(currentBatch)
                        }
                    }

                    if !batch.isEmpty {
                        found.append(contentsOf: batch)
                        let currentBatch = batch
                        onBatch?(currentBatch)
                    }
                }

                // Sort descending by modified date (newest first)
                found.sort { $0.modifiedDate > $1.modifiedDate }
                continuation.resume(returning: found)
            }
        }
    }
}
