//
//  BluetoothService.swift
//  Nearo
//
//  Bluetooth Link Provider (Beta) for Nearo.
//  Provides KDE Connect RFCOMM service discovery and connection handling.
//  Disabled by default.
//

import Foundation
import Combine
import IOBluetooth
import CoreBluetooth

@MainActor
public final class BluetoothService: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = BluetoothService()

    /// KDE Connect official RFCOMM 128-bit service UUID
    public static let kdeConnectServiceUUIDString = "185f3df4-3268-4e3f-9fca-d4d5059915bd"

    public static let userDefaultsKey = "nearo_bluetooth_enabled"

    @Published public private(set) var isEnabled: Bool = false
    @Published public private(set) var localAddress: String?
    @Published public private(set) var pairedBluetoothDevices: [String: String] = [:] // Name -> Address
    @Published public private(set) var connectedBluetoothAddresses: Set<String> = []
    @Published public private(set) var isListening: Bool = false
    @Published public private(set) var statusText: String = "Disabled"

    private var rfcommChannelID: BluetoothRFCOMMChannelID = 1
    private var rfcommNotification: IOBluetoothUserNotification?
    private var sdpServiceRecord: IOBluetoothSDPServiceRecord?
    private var activeChannels: [IOBluetoothRFCOMMChannel] = []
    private var pollTimer: Timer?

    private let authorization: () -> CBManagerAuthorization
    private var wantsToListen = false
    private var permissionManager: CBCentralManager?
    private var permissionWaiters: [CheckedContinuation<Bool, Never>] = []

    public override convenience init() {
        self.init(enabled: UserDefaults.standard.bool(forKey: Self.userDefaultsKey),
                  authorization: { CBManager.authorization })
    }

    init(enabled: Bool, authorization: @escaping () -> CBManagerAuthorization) {
        self.authorization = authorization
        super.init()
        isEnabled = enabled
        statusText = enabled ? "Not listening" : "Disabled (Beta)"
    }

    // MARK: - Lifecycle

    public func start() {
        wantsToListen = true
        restoreListener()
    }

    /// Launch can restore an already authorized listener. Only a feature action
    /// may create a Core Bluetooth manager and bring up the system prompt.
    private func restoreListener() {
        guard wantsToListen, isEnabled, pollTimer == nil else { return }
        switch authorization() {
        case .allowedAlways: break
        case .notDetermined:
            statusText = "Bluetooth access hasn’t been requested."
            return
        default:
            statusText = "Bluetooth access is unavailable. Check System Settings › Privacy & Security › Bluetooth."
            return
        }
        self.localAddress = IOBluetoothHostController.default()?.addressAsString()
        refreshPairedDevices()
        startListening()
        startPolling()
    }

    public func stop() {
        wantsToListen = false
        localAddress = nil
        pairedBluetoothDevices = [:]
        stopListening()
        pollTimer?.invalidate()
        pollTimer = nil
        statusText = "Disabled"
    }

    public func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.userDefaultsKey)
        isEnabled = enabled
        if enabled {
            start()
            if authorization() == .notDetermined {
                Task { @MainActor in
                    guard self.isEnabled, self.wantsToListen else { return }
                    _ = await self.requestAccessForFeature()
                }
            }
            NearoLog("[Bluetooth] Bluetooth (Beta) link provider enabled.")
        } else {
            stop()
            NearoLog("[Bluetooth] Bluetooth link provider disabled.")
        }
    }

    /// Called when opening Calls or explicitly enabling the Bluetooth transport.
    func requestAccessForFeature() async -> Bool {
        switch authorization() {
        case .allowedAlways:
            restoreListener()
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                permissionWaiters.append(continuation)
                if permissionManager == nil {
                    permissionManager = CBCentralManager(delegate: self, queue: .main, options: [
                        CBCentralManagerOptionShowPowerAlertKey: false
                    ])
                }
            }
        default:
            return false
        }
    }

    // MARK: - Paired Devices

    public func refreshPairedDevices() {
        guard wantsToListen, isEnabled, authorization() == .allowedAlways else { return }
        var map: [String: String] = [:]
        if let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
            for device in devices {
                let name = device.nameOrAddress ?? device.name ?? "Unknown"
                let address = device.addressString ?? ""
                if !address.isEmpty {
                    map[name] = address
                }
            }
        }
        self.pairedBluetoothDevices = map
    }

    /// Looks up a known Bluetooth MAC address for a given device name or identity
    public func bluetoothAddress(forDeviceName name: String) -> String? {
        guard isEnabled else { return nil }

        // 1. Direct match in paired devices
        if let direct = pairedBluetoothDevices[name] {
            return direct
        }

        // 2. Case-insensitive or partial match (e.g. "Pixel 10" in "Pixel 10")
        let lower = name.lowercased().trimmingCharacters(in: .whitespaces)
        for (devName, addr) in pairedBluetoothDevices {
            let devLower = devName.lowercased()
            if devLower == lower || devLower.contains(lower) || lower.contains(devLower) {
                return addr
            }
        }

        return nil
    }

    public func isDeviceConnectedViaBluetooth(address: String) -> Bool {
        let clean = address.replacingOccurrences(of: ":", with: "-").lowercased()
        for connected in connectedBluetoothAddresses {
            if connected.replacingOccurrences(of: ":", with: "-").lowercased() == clean {
                return true
            }
        }
        return false
    }

    // MARK: - Listening & SDP Service

    private func startListening() {
        guard rfcommNotification == nil else { return }

        // 1. Register for incoming RFCOMM channel open notifications
        rfcommNotification = IOBluetoothRFCOMMChannel.register(
            forChannelOpenNotifications: self,
            selector: #selector(rfcommChannelOpened(notification:channel:)),
            withChannelID: rfcommChannelID,
            direction: kIOBluetoothUserNotificationChannelDirectionIncoming
        )

        // 2. Publish SDP Service Record for KDE Connect
        publishSDPServiceRecord()

        isListening = (rfcommNotification != nil)
        statusText = isListening ? "Listening on RFCOMM channel \(rfcommChannelID)" : "Failed to bind RFCOMM"
        NearoLog("[Bluetooth] \(statusText)")
    }

    private func stopListening() {
        if let notification = rfcommNotification {
            notification.unregister()
            rfcommNotification = nil
        }

        if let record = sdpServiceRecord {
            record.remove()
            sdpServiceRecord = nil
        }

        for channel in activeChannels {
            channel.close()
        }
        activeChannels.removeAll()
        connectedBluetoothAddresses.removeAll()

        isListening = false
    }

    private func publishSDPServiceRecord() {
        guard sdpServiceRecord == nil else { return }

        // UUID: 185f3df4-3268-4e3f-9fca-d4d5059915bd
        let uuidBytes: [UInt8] = [
            0x18, 0x5f, 0x3d, 0xf4, 0x32, 0x68, 0x4e, 0x3f,
            0x9f, 0xca, 0xd4, 0xd5, 0x05, 0x99, 0x15, 0xbd
        ]

        let dict: [String: Any] = [
            "0001 - ServiceClassIDList": [
                IOBluetoothSDPUUID(data: Data(uuidBytes))
            ],
            "0004 - ProtocolDescriptorList": [
                [IOBluetoothSDPUUID(uuid16: 0x0100)!], // L2CAP
                [IOBluetoothSDPUUID(uuid16: 0x0003)!, UInt8(rfcommChannelID)] // RFCOMM Channel
            ],
            "0100 - ServiceName*": "KDE Connect"
        ]

        if let record = IOBluetoothSDPServiceRecord.publishedServiceRecord(with: dict) {
            sdpServiceRecord = record
            NearoLog("[Bluetooth] Published KDE Connect SDP service record.")
        } else {
            NearoLog("[Bluetooth] Warning: Failed to publish SDP service record.")
        }
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPairedDevices()
                self?.checkConnectedDevices()
            }
        }
    }

    private func checkConnectedDevices() {
        guard wantsToListen, isEnabled, authorization() == .allowedAlways else { return }
        var connected: Set<String> = []
        if let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
            for device in devices {
                if device.isConnected(), let addr = device.addressString {
                    connected.insert(addr)
                }
            }
        }
        self.connectedBluetoothAddresses = connected
    }

    // MARK: - Incoming Connections

    @objc private func rfcommChannelOpened(notification: IOBluetoothUserNotification, channel: IOBluetoothRFCOMMChannel) {
        NearoLog("[Bluetooth] Incoming RFCOMM channel opened from: \(channel.getDevice()?.nameOrAddress ?? "Unknown")")
        channel.setDelegate(self)
        activeChannels.append(channel)

        if let addr = channel.getDevice()?.addressString {
            connectedBluetoothAddresses.insert(addr)
        }
    }
}

extension BluetoothService: @preconcurrency CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central === permissionManager else { return }
        let status = authorization()
        guard status != .notDetermined || central.state == .unsupported else { return }
        let waiters = permissionWaiters
        permissionWaiters.removeAll()
        central.delegate = nil
        permissionManager = nil
        restoreListener()
        for waiter in waiters { waiter.resume(returning: status == .allowedAlways) }
    }
}

// MARK: - IOBluetoothRFCOMMChannelDelegate

extension BluetoothService: IOBluetoothRFCOMMChannelDelegate {
    public func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        if error == kIOReturnSuccess {
            NearoLog("[Bluetooth] RFCOMM channel ready: \(rfcommChannel.getID())")
        } else {
            NearoLog("[Bluetooth] RFCOMM channel open failed: \(error)")
        }
    }

    public func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        NearoLog("[Bluetooth] RFCOMM channel closed.")
        activeChannels.removeAll { $0 == rfcommChannel }
        if let addr = rfcommChannel.getDevice()?.addressString {
            connectedBluetoothAddresses.remove(addr)
        }
    }

    public func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        guard dataLength > 0, let dataPointer = dataPointer else { return }
        let data = Data(bytes: dataPointer, count: dataLength)
        NearoLog("[Bluetooth] Received \(data.count) bytes on RFCOMM channel.")

        // Parse incoming network packets
        if let packet = try? NetworkPacket.unserialize(from: data) {
            NearoLog("[Bluetooth] Packet received over Bluetooth: \(packet.type)")
        }
    }
}
