//
//  NearoLog.swift
//  Nearo
//

import Foundation
import os.log

private let logFileURL = URL(fileURLWithPath: "/tmp/nearo.log")
private let logQueue = DispatchQueue(label: "com.anwar.nearo.log", qos: .utility)
private let dateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

nonisolated public func NearoLog(_ message: String) {
    let timestamp = dateFormatter.string(from: Date())
    let formatted = "[\(timestamp)] \(message)\n"
    print(formatted, terminator: "")

    logQueue.async {
        guard let data = formatted.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logFileURL.path) {
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: logFileURL)
        }
    }
}
