//
//  PhotoThumbnailService.swift
//  Nearo
//
//  High-performance thumbnail generation and caching for phone photos.
//  Uses ImageIO downsampling, decompressed memory caching, and bounded
//  background concurrency so large photos over NFS scroll with zero UI lag.
//

import AppKit
import Foundation
import ImageIO

nonisolated public final class PhotoThumbnailService: @unchecked Sendable {
    public static let shared = PhotoThumbnailService()

    private let memoryCache = NSCache<NSString, NSImage>()
    private let lock = NSLock()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    /// Limit concurrent NFS network reads to 4 workers to prevent overloading phone NFS server.
    private static let nfsLimiter = ConcurrencyLimiter(limit: 4)

    private init() {
        memoryCache.countLimit = 2000
        memoryCache.totalCostLimit = 128 * 1024 * 1024 // 128 MB
    }

    private func cacheDirectory(for deviceId: String) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("Nearo/Thumbnails/\(deviceId)", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func diskCacheURL(for photo: PhonePhoto, deviceId: String) -> URL {
        let safeKey = "\(photo.id)_\(Int(photo.modifiedDate.timeIntervalSince1970))"
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }
            .joined()
        return cacheDirectory(for: deviceId).appendingPathComponent("\(safeKey).jpg")
    }

    /// Completely synchronous, non-blocking check in RAM cache.
    public func cachedThumbnail(for photoId: String) -> NSImage? {
        memoryCache.object(forKey: photoId as NSString)
    }

    public func cachedThumbnail(for photo: PhonePhoto) -> NSImage? {
        cachedThumbnail(for: photo.id)
    }

    public func setMemoryCache(_ image: NSImage, for photoId: String) {
        memoryCache.setObject(image, forKey: photoId as NSString)
    }

    /// Retrieve or generate a downsampled thumbnail.
    /// Fast-path returns from RAM; background tasks load from disk or generate from phone NFS.
    public func thumbnail(for photo: PhonePhoto, deviceId: String, maxPixelSize: CGFloat = 320) async -> NSImage? {
        let cacheKey = photo.id as NSString
        if let cached = memoryCache.object(forKey: cacheKey) {
            return cached
        }

        let diskFile = diskCacheURL(for: photo, deviceId: deviceId)

        // Deduplicate in-flight requests
        lock.lock()
        if let running = inFlight[photo.id] {
            lock.unlock()
            return await running.value
        }

        let task = Task.detached(priority: .userInitiated) { () -> NSImage? in
            // Step 1: Check disk cache and decompress immediately on background thread
            if FileManager.default.fileExists(atPath: diskFile.path),
               let source = CGImageSourceCreateWithURL(diskFile as CFURL, nil),
               let cgImage = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) {
                let diskImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                PhotoThumbnailService.shared.setMemoryCache(diskImage, for: photo.id)
                return diskImage
            }

            guard !Task.isCancelled else { return nil }

            // Step 2: Generate thumbnail across NFS using bounded concurrency limiter
            return await Self.nfsLimiter.withPermit {
                guard !Task.isCancelled else { return nil }
                return Self.generateThumbnail(from: photo.url, diskFile: diskFile, maxPixelSize: maxPixelSize)
            }
        }

        inFlight[photo.id] = task
        lock.unlock()

        let image = await task.value

        lock.lock()
        inFlight[photo.id] = nil
        lock.unlock()

        if let image {
            memoryCache.setObject(image, forKey: cacheKey)
        }
        return image
    }

    private static func generateThumbnail(from sourceURL: URL, diskFile: URL, maxPixelSize: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            return nil
        }

        // Fast path: Use embedded thumbnail if present; create only if absent
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        // Save decompressed thumbnail to disk cache atomically for instant future reads
        let rep = NSBitmapImageRep(cgImage: cgImage)
        if let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) {
            try? jpegData.write(to: diskFile, options: .atomic)
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

// MARK: - Concurrency Limiter Actor

actor ConcurrencyLimiter {
    private let limit: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    func withPermit<T: Sendable>(_ operation: @Sendable () async -> T) async -> T {
        await acquire()
        defer { release() }
        return await operation()
    }

    private func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.resume()
        } else {
            running -= 1
        }
    }
}
