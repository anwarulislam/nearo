//
//  TrustStore.swift
//  Nearo
//

import Foundation
import Combine
import CryptoKit

public final class TrustStore: ObservableObject, @unchecked Sendable {
    public static let shared = TrustStore()

    @Published public private(set) var pairedDevices: [String: PairedDevice] = [:]

    private let userDefaultsKey = "nearo_paired_devices"
    private let lock = NSLock()

    private init() {
        loadDevices()
    }

    /// Build 1.2 shipped with the author's own phone pre-trusted on every install.
    /// It is removed on load so nobody trusts a device they never paired.
    private static let removedPreloadedDeviceIds: Set<String> = ["5bbcb3e152d34b9597997d39ca4587ce"]

    private func loadDevices() {
        var stored = Self.decode(key: userDefaultsKey) ?? Self.decode(key: "kdeconnect_paired_devices") ?? []
        if stored.isEmpty {
            stored = Self.loadFromKdeConnectPreferences()
        }
        let kept = stored.filter { !Self.removedPreloadedDeviceIds.contains($0.deviceId) }

        self.pairedDevices = Dictionary(kept.map { ($0.deviceId, $0) }, uniquingKeysWith: { _, latest in latest })

        // Persist when migrating from the legacy key or when a preloaded entry was dropped.
        if kept.count != stored.count || UserDefaults.standard.data(forKey: userDefaultsKey) == nil {
            saveDevices()
        }
    }

    private static func loadFromKdeConnectPreferences() -> [PairedDevice] {
        let fm = FileManager.default
        guard let libraryDir = fm.urls(for: .libraryDirectory, in: .userDomainMask).first else { return [] }
        let trustedDevicesFile = libraryDir.appendingPathComponent("Preferences/kdeconnect/trusted_devices")
        guard let content = try? String(contentsOf: trustedDevicesFile, encoding: .utf8) else { return [] }

        var result: [PairedDevice] = []
        var currentId = ""
        var currentName = ""
        var currentCert = ""
        var currentTypeStr = "phone"

        let finishCurrent = {
            guard !currentId.isEmpty, !currentCert.isEmpty else { return }
            let cleanPem = currentCert
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "")
                .replacingOccurrences(of: "-----END CERTIFICATE-----", with: "")
                .components(separatedBy: .whitespacesAndNewlines)
                .joined()
            if let der = Data(base64Encoded: cleanPem) {
                let digest = SHA256.hash(data: der)
                let fp = digest.map { String(format: "%02x", $0) }.joined(separator: ":")
                let dev = PairedDevice(
                    deviceId: currentId,
                    deviceName: currentName.isEmpty ? "Phone" : currentName,
                    deviceType: DeviceType.from(string: currentTypeStr),
                    certificateFingerprint: fp,
                    certificatePEM: currentCert.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\"", with: "")
                )
                result.append(dev)
                NearoLog("[TrustStore] Migrated KDE Connect device \(dev.deviceName) (\(dev.deviceId)) with fingerprint \(fp)")
            }
        }

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("[") && line.hasSuffix("]") {
                finishCurrent()
                currentId = String(line.dropFirst().dropLast())
                currentName = ""
                currentCert = ""
                currentTypeStr = "phone"
            } else if line.hasPrefix("name=") {
                currentName = String(line.dropFirst(5))
            } else if line.hasPrefix("certificate=") {
                currentCert = String(line.dropFirst(12))
            } else if line.hasPrefix("type=") {
                currentTypeStr = String(line.dropFirst(5))
            }
        }
        finishCurrent()
        return result
    }

    private static func decode(key: String) -> [PairedDevice]? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        do {
            let list = try JSONDecoder().decode([PairedDevice].self, from: data)
            return list.isEmpty ? nil : list
        } catch {
            // Never silently treat unreadable pairings as "none": that would let
            // the next save overwrite them. Keep the raw bytes for recovery.
            NearoLog("[TrustStore] Could not read \(key): \(error)")
            UserDefaults.standard.set(data, forKey: "\(key)_unreadable_backup")
            return nil
        }
    }

    private func saveDevices() {
        let list = Array(pairedDevices.values)
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    public func isTrusted(deviceId: String) -> Bool {
        lock.withLock {
            pairedDevices[deviceId] != nil
        }
    }

    public func pairedDevice(for deviceId: String) -> PairedDevice? {
        lock.withLock {
            pairedDevices[deviceId]
        }
    }

    public func add(device: PairedDevice) {
        lock.withLock {
            self.pairedDevices[device.deviceId] = device
            self.saveDevices()
        }
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    /// Forgets a paired device. `reason` is logged so a lost pairing can always be traced.
    public func remove(deviceId: String, reason: String) {
        lock.withLock {
            let name = self.pairedDevices[deviceId]?.deviceName ?? "unknown"
            NearoLog("[TrustStore] Removing \(name) (\(deviceId)): \(reason)")
            self.pairedDevices.removeValue(forKey: deviceId)
            self.saveDevices()
        }
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    public func updateLastSeen(deviceId: String) {
        lock.withLock {
            guard var device = self.pairedDevices[deviceId] else { return }
            device.lastSeenDate = Date()
            self.pairedDevices[deviceId] = device
            self.saveDevices()
        }
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    public func updateSettings(deviceId: String, clipboard: Bool, notifications: Bool) {
        lock.withLock {
            guard var device = self.pairedDevices[deviceId] else { return }
            device.isClipboardSyncEnabled = clipboard
            device.isNotificationSyncEnabled = notifications
            self.pairedDevices[deviceId] = device
            self.saveDevices()
        }
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
}
