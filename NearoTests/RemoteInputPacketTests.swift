import Foundation
import Testing
@testable import Nearo

struct RemoteInputPacketTests {
    @Test func submittedTextUsesAndroidsOrdinaryKeyCode() throws {
        let draft = "Hello, ফোন 👋"
        let data = try MousepadPlugin.request(body: ["key": draft]).serialize()
        let packet = try JSONDecoder().decode(NetworkPacket.self, from: data)
        #expect(packet.type == MousepadPlugin.requestType)
        #expect(packet.string(for: "key") == draft)
        #expect(packet.int(for: "specialKey", default: -1) == 0)
        #expect(!MousepadPlugin.request(body: ["singleclick": true]).has("specialKey"))
    }
}
