//
//  PhotosTests.swift
//  NearoTests
//
//  Unit tests for PhonePhoto, PhotosScanner, and PhotoThumbnailService.
//

import AppKit
import Foundation
import Testing
@testable import Nearo

struct PhotosTests {
    @Test func phonePhotoModelPropertiesAndFormatting() {
        let date = Date(timeIntervalSince1970: 1731600000)
        let photo = PhonePhoto(
            id: "DCIM/Camera/IMG_001.jpg",
            name: "IMG_001.jpg",
            relativePath: "DCIM/Camera/IMG_001.jpg",
            fullPath: "/Volumes/Phone/DCIM/Camera/IMG_001.jpg",
            fileSize: 4_500_000,
            modifiedDate: date,
            folder: "Camera"
        )

        #expect(photo.id == "DCIM/Camera/IMG_001.jpg")
        #expect(photo.name == "IMG_001.jpg")
        #expect(photo.folder == "Camera")
        #expect(photo.url.path == "/Volumes/Phone/DCIM/Camera/IMG_001.jpg")
        #expect(!photo.formattedSize.isEmpty)
    }

    @Test func phonePhotoCodableRoundtrip() throws {
        let original = [
            PhonePhoto(
                id: "p1",
                name: "pic1.jpg",
                relativePath: "DCIM/Camera/pic1.jpg",
                fullPath: "/test/pic1.jpg",
                fileSize: 1024,
                modifiedDate: Date(timeIntervalSince1970: 1700000000),
                folder: "Camera"
            ),
            PhonePhoto(
                id: "p2",
                name: "pic2.png",
                relativePath: "Pictures/Screenshots/pic2.png",
                fullPath: "/test/pic2.png",
                fileSize: 2048,
                modifiedDate: Date(timeIntervalSince1970: 1700001000),
                folder: "Screenshots"
            )
        ]

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([PhonePhoto].self, from: encoded)

        #expect(decoded.count == 2)
        #expect(decoded[0].id == "p1")
        #expect(decoded[0].name == "pic1.jpg")
        #expect(decoded[1].id == "p2")
        #expect(decoded[1].folder == "Screenshots")
    }

    @Test func photosScannerSavesAndLoadsCache() {
        let testDeviceId = "test_device_\(UUID().uuidString)"
        let photos = [
            PhonePhoto(
                id: "test1",
                name: "cached_img.jpg",
                relativePath: "DCIM/cached_img.jpg",
                fullPath: "/tmp/cached_img.jpg",
                fileSize: 5000,
                modifiedDate: Date(),
                folder: "Camera"
            )
        ]

        PhotosScanner.shared.saveCachedPhotos(photos, for: testDeviceId)
        let loaded = PhotosScanner.shared.loadCachedPhotos(for: testDeviceId)

        #expect(loaded != nil)
        #expect(loaded?.count == 1)
        #expect(loaded?.first?.name == "cached_img.jpg")
    }

    @Test func photosScannerDiscoversAndSortsPhotos() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("PhotosScannerTest_\(UUID().uuidString)")
        let cameraDir = tempDir.appendingPathComponent("DCIM/Camera")
        let picturesDir = tempDir.appendingPathComponent("Pictures")
        let downloadDir = tempDir.appendingPathComponent("Download")

        try FileManager.default.createDirectory(at: cameraDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: picturesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: downloadDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create dummy test images
        let file1 = cameraDir.appendingPathComponent("IMG_01.jpg")
        let file2 = picturesDir.appendingPathComponent("Art.png")
        let file3 = downloadDir.appendingPathComponent("Wallpaper.webp")
        let ignoredTextFile = downloadDir.appendingPathComponent("Notes.txt")
        let hiddenFile = cameraDir.appendingPathComponent(".hidden.jpg")

        try "image1".write(to: file1, atomically: true, encoding: .utf8)
        try "image2".write(to: file2, atomically: true, encoding: .utf8)
        try "image3".write(to: file3, atomically: true, encoding: .utf8)
        try "text".write(to: ignoredTextFile, atomically: true, encoding: .utf8)
        try "hidden".write(to: hiddenFile, atomically: true, encoding: .utf8)

        var streamedCount = 0
        let scanned = await PhotosScanner.shared.scan(mountURL: tempDir) { batch in
            streamedCount += batch.count
        }

        #expect(scanned.count == 3)
        let names = Set(scanned.map(\.name))
        #expect(names.contains("IMG_01.jpg"))
        #expect(names.contains("Art.png"))
        #expect(names.contains("Wallpaper.webp"))
        #expect(!names.contains("Notes.txt"))
        #expect(!names.contains(".hidden.jpg"))
    }

    @Test func photoThumbnailServiceGeneratesAndCachesThumbnails() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ThumbnailTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a real test bitmap image (800x600)
        let imageSize = NSSize(width: 800, height: 600)
        let image = NSImage(size: imageSize)
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(origin: .zero, size: imageSize).fill()
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpg = rep.representation(using: .jpeg, properties: [:]) else {
            Issue.record("Failed to create test JPEG")
            return
        }

        let testImageURL = tempDir.appendingPathComponent("large_photo.jpg")
        try jpg.write(to: testImageURL)

        let photo = PhonePhoto(
            id: "thumb_test_01",
            name: "large_photo.jpg",
            relativePath: "large_photo.jpg",
            fullPath: testImageURL.path,
            fileSize: Int64(jpg.count),
            modifiedDate: Date(),
            folder: "Test"
        )

        let testDeviceId = "thumb_device_\(UUID().uuidString)"

        // Generate downsampled thumbnail (target max 160)
        let thumb = await PhotoThumbnailService.shared.thumbnail(for: photo, deviceId: testDeviceId, maxPixelSize: 160)
        #expect(thumb != nil)
        if let thumb {
            #expect(thumb.size.width <= 160)
            #expect(thumb.size.height <= 160)
        }

        // Test RAM cache hit
        let ramThumb = await PhotoThumbnailService.shared.cachedThumbnail(for: photo)
        #expect(ramThumb != nil)
    }
}
