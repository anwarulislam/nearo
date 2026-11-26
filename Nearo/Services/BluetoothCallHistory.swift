import Foundation
import IOBluetooth
import CoreBluetooth

enum PhoneHistoryError: LocalizedError {
    case permission, pairing(String), discovery, unsupported, access, timeout, invalidResponse

    var errorDescription: String? {
        switch self {
        case .permission: "Allow Nearo to use Bluetooth in System Settings › Privacy & Security › Bluetooth, then sync again."
        case .pairing(let name): "Pair \(name) in macOS Bluetooth settings. Its Bluetooth name must match the phone selected in Nearo."
        case .discovery: "Couldn’t reach the phone over Bluetooth. Bring it nearby, turn on Bluetooth, and sync again."
        case .unsupported: "This phone doesn’t offer Bluetooth phonebook sharing to this Mac."
        case .access: "Allow contact and call history sharing for this Mac in the phone’s Bluetooth settings, then sync again."
        case .timeout: "The phone didn’t respond. Unlock it, check for a Bluetooth sharing request, and sync again."
        case .invalidResponse: "The phone returned an unreadable call history."
        }
    }
}

/// PullPhoneBook on the Bluetooth Phone Book Access Profile (PBAP), using the
/// combined call-history object. Each instance owns one SDP/RFCOMM exchange.
@MainActor
final class BluetoothCallHistory: NSObject, IOBluetoothRFCOMMChannelDelegate {
    private static let service = IOBluetoothSDPUUID(uuid16: 0x112f)!
    private let timeZone: TimeZone
    private let phone: IOBluetoothDevice
    private var channel: IOBluetoothRFCOMMChannel?
    private var completion: CheckedContinuation<[CallEntry], Error>?
    private var timeout: Task<Void, Never>?
    private var received = [UInt8]()
    private var cards = Data()
    private var connected = false
    private var connectionID: [UInt8] = []

    init(name: String, address: String?, timeZone: TimeZone = .current) throws {
        self.timeZone = timeZone
        guard CBManager.authorization == .allowedAlways else {
            throw PhoneHistoryError.permission
        }
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        let matches = paired.filter { device in
            if let address {
                return device.addressString?.replacingOccurrences(of: "-", with: ":").lowercased()
                    == address.replacingOccurrences(of: "-", with: ":").lowercased()
            }
            return device.name?.caseInsensitiveCompare(name) == .orderedSame
        }
        // IOBluetooth can list the same paired address more than once.
        guard Set(matches.compactMap(\.addressString)).count == 1, let device = matches.first else {
            throw PhoneHistoryError.pairing(name)
        }
        phone = device
    }

    func fetch() async throws -> [CallEntry] {
        defer { withExtendedLifetime(self) {} }
        return try await withCheckedThrowingContinuation { continuation in
            completion = continuation
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(50))
                guard !Task.isCancelled, let self else { return }
                self.finish(.failure(self.phone.isConnected() ? PhoneHistoryError.timeout : PhoneHistoryError.discovery))
            }
            if phone.performSDPQuery(self, uuids: [Self.service]) != kIOReturnSuccess {
                finish(.failure(PhoneHistoryError.discovery))
            }
        }
    }

    @objc func sdpQueryComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        guard completion != nil else { return }
        guard status == kIOReturnSuccess else { finish(.failure(PhoneHistoryError.discovery)); return }
        var id: BluetoothRFCOMMChannelID = 0
        guard let record = device.getServiceRecord(for: Self.service),
              record.getRFCOMMChannelID(&id) == kIOReturnSuccess else {
            finish(.failure(PhoneHistoryError.unsupported))
            return
        }
        var opened: IOBluetoothRFCOMMChannel?
        if device.openRFCOMMChannelAsync(&opened, withChannelID: id, delegate: self) != kIOReturnSuccess {
            finish(.failure(PhoneHistoryError.discovery))
        } else if completion != nil {
            channel = opened
        }
    }

    func rfcommChannelOpenComplete(_ opened: IOBluetoothRFCOMMChannel!, status: IOReturn) {
        guard completion != nil else { return }
        guard status == kIOReturnSuccess else { finish(.failure(PhoneHistoryError.access)); return }
        channel = opened
        // OBEX 1.0, 16 KiB receive limit, PBAP target UUID.
        let target: [UInt8] = [0x79,0x61,0x35,0xf0,0xf0,0xc5,0x11,0xd8,0x09,0x66,0x08,0x00,0x20,0x0c,0x9a,0x66]
        send(0x80, [0x10, 0, 0x40, 0] + Self.header(0x46, target))
    }

    func rfcommChannelClosed(_ channel: IOBluetoothRFCOMMChannel!) {
        finish(.failure(PhoneHistoryError.discovery))
    }

    func rfcommChannelData(_ channel: IOBluetoothRFCOMMChannel!, data pointer: UnsafeMutableRawPointer!, length: Int) {
        guard completion != nil, length > 0, let pointer else { return }
        received += UnsafeBufferPointer(start: pointer.assumingMemoryBound(to: UInt8.self), count: length)
        while received.count >= 3, completion != nil {
            let size = Int(received[1]) << 8 | Int(received[2])
            guard (3...16384).contains(size) else { finish(.failure(PhoneHistoryError.invalidResponse)); return }
            guard received.count >= size else { return }
            let packet = Array(received.prefix(size))
            received.removeFirst(size)
            do { try handle(packet) } catch { finish(.failure(error)) }
        }
    }

    private func handle(_ packet: [UInt8]) throws {
        let code = packet[0]
        guard code == 0xa0 || (connected && code == 0x90) else {
            throw (code == 0xc1 || code == 0xc3) ? PhoneHistoryError.access : PhoneHistoryError.unsupported
        }
        var index = connected ? 3 : 7
        guard index <= packet.count else { throw PhoneHistoryError.invalidResponse }
        while index < packet.count {
            let id = packet[index]
            let size: Int
            switch id >> 6 {
            case 0, 1:
                guard index + 3 <= packet.count else { throw PhoneHistoryError.invalidResponse }
                size = Int(packet[index+1]) << 8 | Int(packet[index+2])
                guard size >= 3 else { throw PhoneHistoryError.invalidResponse }
            case 2: size = 2
            default: size = 5
            }
            guard index + size <= packet.count else { throw PhoneHistoryError.invalidResponse }
            if id == 0xcb { connectionID = Array(packet[index..<index+size]) }
            if connected && (id == 0x48 || id == 0x49) {
                guard cards.count + size <= 2_000_000 else { throw PhoneHistoryError.invalidResponse }
                cards.append(contentsOf: packet[index+3..<index+size])
            }
            index += size
        }
        if !connected {
            connected = true
            let name = Array(("telecom/cch.vcf" + "\0").data(using: .utf16BigEndian)!)
            let type = Array("x-bt/phonebook".utf8) + [0]
            // MaxListCount (200), vCard format (3.0).
            let parameters: [UInt8] = [4, 2, 0, UInt8(CallHistory.limit), 7, 1, 1]
            send(0x83, connectionID + Self.header(0x01, name) + Self.header(0x42, type) + Self.header(0x4c, parameters))
        } else if code == 0x90 {
            send(0x83, connectionID)
        } else {
            let entries = try Self.parse(cards, timeZone: timeZone)
            finish(.success(entries))
        }
    }

    private static func header(_ id: UInt8, _ body: [UInt8]) -> [UInt8] {
        let size = body.count + 3
        return [id, UInt8(size >> 8), UInt8(truncatingIfNeeded: size)] + body
    }

    private func send(_ opcode: UInt8, _ body: [UInt8]) {
        guard let channel else { finish(.failure(PhoneHistoryError.discovery)); return }
        var bytes = Self.header(opcode, body)
        let status = bytes.withUnsafeMutableBytes {
            channel.writeSync($0.baseAddress, length: UInt16($0.count))
        }
        if status != kIOReturnSuccess { finish(.failure(PhoneHistoryError.discovery)) }
    }

    private func finish(_ result: Result<[CallEntry], Error>) {
        guard let continuation = completion else { return }
        completion = nil
        timeout?.cancel()
        channel?.setDelegate(nil)
        channel?.close()
        channel = nil
        continuation.resume(with: result)
    }

    static func parse(_ data: Data, timeZone: TimeZone = .current) throws -> [CallEntry] {
        guard let text = String(data: data, encoding: .utf8) else { throw PhoneHistoryError.invalidResponse }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        var calls: [CallEntry] = []
        for card in text.components(separatedBy: "END:VCARD") {
            let lines = card.components(separatedBy: .newlines)
            guard let stamp = lines.first(where: { $0.uppercased().hasPrefix("X-IRMC-CALL-DATETIME;") }),
                  let colon = stamp.firstIndex(of: ":") else { continue }
            let types = stamp[..<colon].uppercased().components(separatedBy: CharacterSet(charactersIn: ";="))
            let kind: CallEntry.Kind
            if types.contains("MISSED") { kind = .missed }
            else if types.contains("DIALED") { kind = .outgoing }
            else if types.contains("RECEIVED") { kind = .incoming }
            else { continue }
            let value = stamp[stamp.index(after: colon)...]
            formatter.timeZone = value.hasSuffix("Z") ? TimeZone(secondsFromGMT: 0) : timeZone
            guard let date = formatter.date(from: String(value.trimmingCharacters(in: CharacterSet(charactersIn: "Z")))) else { continue }
            let contact = VCard.parse(card)
            let tel = lines.first { $0.split(separator: ";", maxSplits: 1).first?.uppercased() == "TEL" || $0.uppercased().hasPrefix("TEL:") }
            let number = contact?.numbers.first ?? tel?.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init)
            calls.append(CallEntry(date: date, kind: kind, number: number, name: contact?.name, fromPhone: true))
        }
        if calls.isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw PhoneHistoryError.invalidResponse }
        return calls
    }
}
