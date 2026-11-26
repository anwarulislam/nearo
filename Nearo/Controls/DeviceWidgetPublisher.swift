import AppKit
import Observation
import WidgetKit

@MainActor final class DeviceWidgetPublisher {
    private let model: NearoAppModel
    private var last: DeviceWidgetSnapshot?

    init(model: NearoAppModel) {
        self.model = model
        refresh()
    }

    private func refresh() {
        let snapshot = withObservationTracking {
            DeviceWidgetSnapshot(processID: ProcessInfo.processInfo.processIdentifier,
                primaryID: model.primaryDevice?.id ?? model.selectedDeviceId,
                devices: model.pairedDevices.map { device in
                    WidgetDeviceStatus(id: device.id, name: device.name, symbol: device.deviceType.systemImageName,
                        connected: device.isConnected, battery: device.isConnected ? device.batteryPercent : nil,
                        charging: device.isConnected && device.isCharging,
                        title: device.isConnected ? device.nowPlayingTitle : nil,
                        artist: device.isConnected ? device.nowPlayingArtist : nil)
                })
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        publish(snapshot)
    }

    func stopped() {
        guard var snapshot = last else { return }
        snapshot.processID = 0
        publish(snapshot)
    }

    private func publish(_ snapshot: DeviceWidgetSnapshot) {
        guard last != snapshot, let data = try? JSONEncoder().encode(snapshot) else { return }
        let board = NSPasteboard(name: DeviceWidgetSnapshot.board)
        board.clearContents()
        if board.setData(data, forType: DeviceWidgetSnapshot.type) {
            last = snapshot
            WidgetCenter.shared.reloadTimelines(ofKind: DeviceWidgetSnapshot.kind)
        }
    }
}
