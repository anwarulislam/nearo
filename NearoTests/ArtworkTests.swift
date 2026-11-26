//
//  ArtworkTests.swift
//  NearoTests
//

import AppKit
import ImageIO
import Testing
@testable import Nearo

struct ArtworkTests {
    private func bitmap(_ side: Int) throws -> NSBitmapImageRep {
        try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    }

    private func pixelSize(_ data: Data) throws -> Int {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil)).width
    }

    /// Safari's video artwork is TIFF, which Android can't decode.
    @Test func convertsTIFFToJPEG() throws {
        let tiff = try #require(bitmap(64).tiffRepresentation)
        let (data, mimeType) = try #require(NowPlayingReader.phoneReadable(tiff))
        #expect(mimeType == "image/jpeg")
        #expect(data.starts(with: [0xFF, 0xD8]))
    }

    @Test func keepsSmallJPEGsAndShrinksLargeImages() throws {
        let jpeg = try #require(bitmap(300).representation(using: .jpeg, properties: [:]))
        let kept = try #require(NowPlayingReader.phoneReadable(jpeg))
        #expect(kept.0 == jpeg)

        let large = try #require(bitmap(2000).representation(using: .png, properties: [:]))
        let shrunk = try #require(NowPlayingReader.phoneReadable(large))
        #expect(shrunk.1 == "image/jpeg")
        #expect(try pixelSize(shrunk.0) == 1024)
    }

    @Test func readsAndroidClockAndTimeZone() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let sample = try #require(HandsetClock(sample: "1800000120 +0545\nAsia/Kathmandu\n24\n", received: now))
        #expect(sample.adjustment == 120)
        #expect(sample.zone.identifier == "Asia/Kathmandu")
        #expect(sample.uses24Hours == true)
        let fallback = try #require(HandsetClock(sample: "1800000000 -0330\n\nnull", received: now))
        #expect(fallback.zone.secondsFromGMT() == -12600)
        #expect(fallback.uses24Hours == nil)
        #expect(HandsetClock(sample: "device offline", received: now) == nil)
    }

    @MainActor @Test func handsetWallpaperIsCachedPerDevice() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let pictures = root.appending(path: "Pictures/Nearo")
        try FileManager.default.createDirectory(at: pictures, withIntermediateDirectories: true)
        let source = try #require(bitmap(800).representation(using: .png, properties: [:]))
        try source.write(to: pictures.appending(path: "wallpaper.png"))
        let cache = root.appending(path: "cache")
        let preview = HandsetPreview(deviceID: "phone/a", cacheDirectory: cache)
        preview.refreshIfNeeded(mount: root, address: nil)
        for _ in 0..<100 where preview.jpeg == nil { try await Task.sleep(for: .milliseconds(20)) }
        let jpeg = try #require(preview.jpeg)
        #expect(try pixelSize(jpeg) == 384)
        let restored = HandsetPreview(deviceID: "phone/a", cacheDirectory: cache)
        restored.refreshIfNeeded(mount: nil, address: nil)
        let other = HandsetPreview(deviceID: "phone/b", cacheDirectory: cache)
        other.refreshIfNeeded(mount: nil, address: nil)
        for _ in 0..<100 where restored.jpeg == nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(restored.jpeg == jpeg)
        #expect(other.jpeg == nil)
        restored.forget()
        #expect(try FileManager.default.contentsOfDirectory(atPath: cache.path).isEmpty)
    }

    @Test func rejectsNonImages() {
        #expect(NowPlayingReader.phoneReadable(Data("not an image".utf8)) == nil)
    }
}
