//
//  SettingsViewModel.swift
//  Nearo
//
//  Native macOS SwiftUI @Observable view model for app settings and preferences.
//

import SwiftUI
import Combine
import Observation
import ServiceManagement
import UserNotifications
import ApplicationServices

@Observable
@MainActor
public final class SettingsViewModel {
    public static let shared = SettingsViewModel()

    public var deviceName: String = DeviceIdentity.shared.deviceName
    public var deviceId: String = DeviceIdentity.shared.deviceId
    public var certificateFingerprint: String = DeviceIdentity.shared.certificateFingerprint
    public var pairedDevices: [PairedDevice] = []
    public var launchAtLogin: Bool = false
    public var notificationAuthStatus: UNAuthorizationStatus = .notDetermined
    public var isAccessibilityTrusted: Bool = false
    public var tailscaleStatus: TailscaleStatus = .notInstalled
    public var isTailscaleDiscoveryEnabled: Bool = TailscaleDiscovery.isEnabled {
        didSet {
            guard !isMockMode, oldValue != isTailscaleDiscoveryEnabled else { return }
            UserDefaults.standard.set(isTailscaleDiscoveryEnabled, forKey: TailscaleDiscovery.enabledKey)
            NearoService.shared.refreshTailscale()
        }
    }

    public var isBluetoothEnabled: Bool = BluetoothService.shared.isEnabled {
        didSet {
            guard !isMockMode, oldValue != isBluetoothEnabled else { return }
            BluetoothService.shared.setEnabled(isBluetoothEnabled)
            localBluetoothAddress = BluetoothService.shared.localAddress
            pairedBluetoothDevices = BluetoothService.shared.pairedBluetoothDevices
            bluetoothStatusText = BluetoothService.shared.statusText
        }
    }
    public var localBluetoothAddress: String? = BluetoothService.shared.localAddress
    public var pairedBluetoothDevices: [String: String] = BluetoothService.shared.pairedBluetoothDevices
    public var bluetoothStatusText: String = BluetoothService.shared.statusText

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    private var isMockMode: Bool = false

    public init(isMock: Bool = false) {
        self.isMockMode = isMock
        if !isMock {
            refresh()
            NearoService.shared.$tailscaleStatus
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.tailscaleStatus = $0 }
                .store(in: &cancellables)
            BluetoothService.shared.$localAddress
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.localBluetoothAddress = $0 }
                .store(in: &cancellables)
            BluetoothService.shared.$pairedBluetoothDevices
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.pairedBluetoothDevices = $0 }
                .store(in: &cancellables)
            BluetoothService.shared.$statusText
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.bluetoothStatusText = $0 }
                .store(in: &cancellables)
        }
    }

    public func refresh() {
        guard !isMockMode else { return }
        self.deviceName = DeviceIdentity.shared.deviceName
        self.deviceId = DeviceIdentity.shared.deviceId
        self.certificateFingerprint = DeviceIdentity.shared.certificateFingerprint
        reloadPairedDevices()
        self.isAccessibilityTrusted = AXIsProcessTrusted()
        self.checkLaunchAtLoginStatus()
        self.refreshNotificationStatus()
        self.localBluetoothAddress = BluetoothService.shared.localAddress
        self.pairedBluetoothDevices = BluetoothService.shared.pairedBluetoothDevices
        self.bluetoothStatusText = BluetoothService.shared.statusText
    }

    public func saveDeviceName(_ newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.deviceName = trimmed
        DeviceIdentity.shared.deviceName = trimmed
        UserDefaults.standard.set(trimmed, forKey: "nearo_device_name")
        NearoService.shared.refreshAdvertisement()
    }

    public func unpair(deviceId: String) {
        NearoService.shared.unpair(deviceId: deviceId)
        reloadPairedDevices()
    }

    public func setSync(deviceId: String, clipboard: Bool, notifications: Bool) {
        guard !isMockMode else { return }
        TrustStore.shared.updateSettings(deviceId: deviceId, clipboard: clipboard, notifications: notifications)
        reloadPairedDevices()
    }

    /// Port the TCP listener actually bound, which peers dial back on.
    public var listeningPort: Int { DeviceIdentity.shared.advertisedTCPPort }

    private func reloadPairedDevices() {
        self.pairedDevices = TrustStore.shared.pairedDevices.values
            .sorted { $0.deviceName.localizedStandardCompare($1.deviceName) == .orderedAscending }
    }

    private func checkLaunchAtLoginStatus() {
        let service = SMAppService.mainApp
        self.launchAtLogin = (service.status == .enabled)
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                }
            }
            self.launchAtLogin = (service.status == .enabled)
        } catch {
            NearoLog("[SettingsViewModel] Failed to toggle launch at login: \(error)")
            self.launchAtLogin = (service.status == .enabled)
        }
    }

    public func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.notificationAuthStatus = settings.authorizationStatus
            }
        }
    }

    public func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.refreshNotificationStatus()
            }
        }
    }

    public func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    public func promptAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.isAccessibilityTrusted = AXIsProcessTrusted()
        }
    }

    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Mocks for Previews

    #if DEBUG
    public static func mock() -> SettingsViewModel {
        let vm = SettingsViewModel(isMock: true)
        vm.deviceName = "Studio Mac"
        vm.deviceId = "a4bcabf07456409a872949f339aeff16"
        vm.certificateFingerprint = "91:CC:44:54:B6:F9:AF:A6:BE:92:C8:B3:9E:5A:26:55:A7:0D:7E:A9:E3:66:8D:2D:4B:D9:8E:50:0D:40:EF:1E"
        vm.pairedDevices = [
            PairedDevice(
                deviceId: "mock_phone",
                deviceName: DemoDevices.phone,
                deviceType: .phone,
                certificateFingerprint: "F7:99:9F:49:20:D9:5F:0C:77:30:22:09:3C:FD:90:A6:4E:96:0E:12:A0:E2:00:4F:73:16:70:31:66:D2:48:6E",
                pairedDate: Date().addingTimeInterval(-86400 * 5)
            )
        ]
        vm.launchAtLogin = true
        vm.tailscaleStatus = .running(selfIP: "100.96.0.10", phones: [
            TailscalePeer(name: DemoDevices.phone, ip: "100.96.0.46", os: "android")
        ])
        vm.notificationAuthStatus = .authorized
        vm.isAccessibilityTrusted = true
        return vm
    }

    public static func mockDenied() -> SettingsViewModel {
        let vm = SettingsViewModel.mock()
        vm.notificationAuthStatus = .denied
        vm.isAccessibilityTrusted = false
        return vm
    }
    #endif
}
