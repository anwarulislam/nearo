import Foundation
import Testing
@testable import Nearo

@MainActor
struct CallHistoryTests {
    private func packet(_ event: String, number: String? = nil, cancelled: Bool = false) -> NetworkPacket {
        var body: [String: Any] = ["event": event]
        body["phoneNumber"] = number
        if cancelled { body["isCancel"] = "true" }
        return NetworkPacket(type: "kdeconnect.telephony", body: body)
    }

    @Test func groupsCallTransitionsAndKeepsSubsequentCallsDistinct() throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = CallHistory(defaults: defaults)
        let ring = packet("ringing", number: "1234")
        history.record(ring, for: "phone")
        history.record(ring, for: "phone")
        let first = try #require(history.entries["phone"]?.first)
        history.record(packet("talking"), for: "phone")
        history.record(packet("talking", cancelled: true), for: "phone")
        history.record(packet("ringing", number: "1234"), for: "phone")
        history.record(packet("ringing", cancelled: true), for: "phone")
        let missed = packet("missedCall")
        history.record(missed, for: "phone")
        history.record(missed, for: "phone")
        history.record(packet("sms"), for: "phone")
        let calls = try #require(history.entries["phone"])
        #expect(calls.map(\.kind) == [.missed, .answered])
        #expect(calls[0].number == "1234")
        #expect(calls[1].id == first.id && calls[1].date == first.date)
    }

    @Test func separatesDevicesAndConnectionSessionsAndRemovesPersistedHistory() throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = CallHistory(defaults: defaults)
        history.record(packet("ringing"), for: "a")
        history.record(packet("talking"), for: "b")
        history.disconnect("a")
        history.record(packet("talking"), for: "a")
        let restored = CallHistory(defaults: defaults)
        restored.load("a")
        restored.load("b")
        #expect(restored.entries["a"]?.map(\.kind) == [.connected, .incoming])
        #expect(restored.entries["b"]?.map(\.kind) == [.connected])
        restored.forget("a")
        restored.load("a")
        #expect(restored.entries["a"] == [])
        #expect(restored.entries["b"] == history.entries["b"])
    }

    @Test func retainsTheMostRecentCallsPerDevice() throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = CallHistory(defaults: defaults)
        for index in 0...CallHistory.limit {
            var missed = packet("missedCall", number: String(index))
            missed.id = Int64(index)
            history.record(missed, for: "phone")
        }
        let calls = try #require(history.entries["phone"])
        #expect(calls.count == CallHistory.limit)
        #expect(calls.first?.number == String(CallHistory.limit))
        #expect(calls.last?.number == "1")
    }

    @Test func ignoresUnrelatedCancelsAndDoesNotMergeDifferentCallers() throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = CallHistory(defaults: defaults)
        history.record(packet("ringing", number: "111"), for: "a")
        history.record(packet("talking", number: "222"), for: "a")
        history.record(packet("talking", number: "111", cancelled: true), for: "a")
        history.record(packet("talking", number: "222"), for: "a")
        #expect(history.entries["a"]?.map(\.kind) == [.connected, .incoming])
    }

    @Test func mergesBluetoothCallsWithLiveEventsAndKeepsTheirIdentityOnRefresh() throws {
        let data = Data("""
            BEGIN:VCARD
            VERSION:3.0
            FN:Alex
            TEL;TYPE=CELL:1234
            X-IRMC-CALL-DATETIME;MISSED:20261125T120000Z
            END:VCARD
            BEGIN:VCARD
            VERSION:3.0
            N:;
            TEL:5678
            X-IRMC-CALL-DATETIME;TYPE=DIALED:20261125T110000
            END:VCARD
            """.utf8)
        let utc = try #require(TimeZone(secondsFromGMT: 0))
        let calls = try BluetoothCallHistory.parse(data, timeZone: utc)
        #expect(calls.map(\.kind) == [.missed, .outgoing])
        #expect(calls.map(\.number) == ["1234", "5678"])
        #expect(calls[0].date.timeIntervalSince(calls[1].date) == 3600)
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = CallHistory(defaults: defaults)
        history.record(packet("missedCall", number: "1234"), for: "a", at: calls[0].date.addingTimeInterval(2))
        let id = history.entries["a"]?.first?.id
        history.mergePhoneHistory(calls, for: "a")
        let once = history.entries["a"]
        history.mergePhoneHistory(try BluetoothCallHistory.parse(data, timeZone: utc), for: "a")
        #expect(history.entries["a"] == once)
        #expect(once?.count == 2 && once?.first?.id == id && once?.first?.name == "Alex")
        history.mergePhoneHistory([], for: "a")
        #expect(history.entries["a"] == [])
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["NEARO_TEST_PBAP_PHONE"] != nil))
    func readsPairedPhoneHistory() async throws {
        let name = try #require(ProcessInfo.processInfo.environment["NEARO_TEST_PBAP_PHONE"])
        try #require(await BluetoothService.shared.requestAccessForFeature())
        let source = try BluetoothCallHistory(name: name, address: nil)
        let calls = try await source.fetch()
        #expect(calls.count <= CallHistory.limit)
        print("Phone shared \(calls.count) call history entries.")
    }
}
