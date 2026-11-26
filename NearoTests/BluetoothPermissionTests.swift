import CoreBluetooth
import Testing
@testable import Nearo

@MainActor
struct BluetoothPermissionTests {
    @Test func restoringAnEnabledTransportDoesNotRequestUndeterminedAccess() {
        var checks = 0
        let service = BluetoothService(enabled: true) {
            checks += 1
            return .notDetermined
        }
        #expect(checks == 0)
        service.start()
        #expect(checks == 1)
        #expect(service.isListening == false)
        #expect(service.localAddress == nil)
        #expect(service.bluetoothAddress(forDeviceName: "Phone") == nil)
        #expect(checks == 1)
    }

    @Test(arguments: [CBManagerAuthorization.denied, .restricted])
    func unavailableAccessKeepsTheListenerStopped(_ status: CBManagerAuthorization) async {
        let service = BluetoothService(enabled: true) { status }
        service.start()
        #expect(await service.requestAccessForFeature() == false)
        #expect(service.isListening == false)
    }

    @Test func authorizedCallsCanUseBluetoothWithTheTransportDisabled() async {
        let service = BluetoothService(enabled: false) { .allowedAlways }
        service.start()
        #expect(await service.requestAccessForFeature())
        #expect(service.isListening == false)
    }
}
