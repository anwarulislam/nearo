import Foundation
import AppIntents
import Testing
@testable import Nearo

@MainActor struct NativeControlTests {
    @Test func ringUsesTheSelectedConnectedDevice() async throws {
        guard #available(macOS 26.0, *) else { return }
        let model = NearoAppModel.mock()
        let previous = NearoControlSession.model
        NearoControlSession.model = model
        defer { NearoControlSession.model = previous }

        var rings: [String] = []
        for device in model.connectedDevices {
            let id = device.id
            device.onFindPhone = { rings.append(id) }
        }
        for device in model.connectedDevices {
            model.selectedDeviceId = device.id
            _ = try await NativeControlIntent(.ring).perform()
        }
        #expect(rings == model.connectedDevices.map(\.id))

        let previousPanel = NearoControlSession.showPanel
        defer { NearoControlSession.showPanel = previousPanel }
        var pages: [MenuNavigation.Page] = []
        NearoControlSession.showPanel = { pages.append($0); return true }
        _ = try await NativeControlIntent(.nowPlaying).perform()
        model.connectedDevices = []
        _ = try await NativeControlIntent(.switchDevice).perform()
        await #expect(throws: (any Error).self) { try await NativeControlIntent(.nowPlaying).perform() }
        #expect(pages == [.media, .devices])

        await #expect(throws: (any Error).self) { try await NativeControlIntent(.ring).perform() }
    }
}

@MainActor struct DeviceWidgetTests {
    @Test func twoPinnedWidgetsKeepTheirDevicesWhenSelectionChanges() throws {
        let phone = WidgetDeviceStatus(id: "phone", name: "Pixel", symbol: "iphone", connected: true, battery: 84)
        let tablet = WidgetDeviceStatus(id: "tablet", name: "Galaxy Tab", symbol: "ipad", connected: false)
        var snapshot = DeviceWidgetSnapshot(processID: 0, primaryID: phone.id, devices: [phone, tablet])
        snapshot = try JSONDecoder().decode(DeviceWidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(snapshot.device(pinnedTo: nil) == phone)
        snapshot.primaryID = tablet.id
        #expect(snapshot.device(pinnedTo: nil) == tablet)
        #expect(snapshot.device(pinnedTo: phone.id) == phone)
        #expect(snapshot.device(pinnedTo: tablet.id) == tablet)
        snapshot.devices.removeAll { $0.id == phone.id }
        #expect(snapshot.device(pinnedTo: phone.id) == nil)
    }
}
