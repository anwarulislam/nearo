//
//  PhonePhoto.swift
//  Nearo
//
//  A photo or image stored on the connected phone's storage.
//

import Foundation

nonisolated public struct PhonePhoto: Identifiable, Sendable, Equatable, Hashable, Codable {
    public let id: String
    public let name: String
    public let relativePath: String
    public let fullPath: String
    public let fileSize: Int64
    public let modifiedDate: Date
    public let folder: String

    public init(
        id: String,
        name: String,
        relativePath: String,
        fullPath: String,
        fileSize: Int64,
        modifiedDate: Date,
        folder: String
    ) {
        self.id = id
        self.name = name
        self.relativePath = relativePath
        self.fullPath = fullPath
        self.fileSize = fileSize
        self.modifiedDate = modifiedDate
        self.folder = folder
    }

    public var url: URL {
        URL(fileURLWithPath: fullPath)
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}
