import AppKit
import Foundation

// The share extension also uses a named pasteboard for local device state.
// Keep this payload separate from the general clipboard and from share requests.
struct WidgetDeviceStatus: Codable, Equatable {
    let id: String
    let name: String
    let symbol: String
    let connected: Bool
    var battery: Int?
    var charging = false
    var title: String?
    var artist: String?
}

struct DeviceWidgetSnapshot: Codable, Equatable {
    static let kind = "com.anwar.Nearo.widget.device"
    static let board = NSPasteboard.Name(kind)
    static let type = NSPasteboard.PasteboardType(kind)
    var processID: Int32
    var primaryID: String?
    var devices: [WidgetDeviceStatus]

    func device(pinnedTo id: String?) -> WidgetDeviceStatus? {
        let target = id ?? primaryID
        return devices.first { $0.id == target }
    }

    static func read() -> Self? {
        guard let data = NSPasteboard(name: board).data(forType: type),
              var snapshot = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        if snapshot.processID <= 0 || NSRunningApplication(processIdentifier: snapshot.processID)?.bundleIdentifier != "com.anwar.Nearo" {
            snapshot.devices = snapshot.devices.map { WidgetDeviceStatus(id: $0.id, name: $0.name, symbol: $0.symbol, connected: false) }
        }
        return snapshot
    }
}
