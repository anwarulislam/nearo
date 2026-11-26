import Combine
import Foundation

struct CallEntry: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case incoming, outgoing, answered, missed, connected

        var label: String {
            switch self {
            case .incoming: "Incoming call"
            case .outgoing: "Outgoing call"
            case .answered: "Answered call"
            case .missed: "Missed call"
            case .connected: "Connected call"
            }
        }
    }

    var id = UUID()
    let date: Date
    var kind: Kind
    var number: String?
    var name: String?
    var fromPhone: Bool?

    func caller(in contacts: ContactBook) -> String {
        if let name, name != number { return name }
        return number.flatMap { contacts.contact(for: $0)?.name } ?? number ?? "Unknown caller"
    }
}

/// KDE Connect sends state changes for a call, without a call ID or a history query.
final class CallHistory: ObservableObject {
    private enum Event: String { case ringing, talking, missedCall }

    private struct Pending {
        let entryID: UUID
        var event: Event
        var cancelledAt: Date?

        func continues(with next: Event, at date: Date) -> Bool {
            switch event {
            case .ringing:
                guard let cancelledAt else { return true }
                return next != .ringing && date.timeIntervalSince(cancelledAt) <= 5
            case .talking:
                return next == .talking
            case .missedCall:
                return false
            }
        }
    }

    static let limit = 200
    @Published private(set) var entries: [String: [CallEntry]] = [:]
    private var pending: [String: Pending] = [:]
    private var lastMissedPacket: [String: Int64] = [:]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(_ device: String) {
        guard entries[device] == nil else { return }
        let saved = defaults.data(forKey: key(device))
        entries[device] = saved.flatMap { try? JSONDecoder().decode([CallEntry].self, from: $0) } ?? []
    }

    func disconnect(_ device: String) {
        pending[device] = nil
        lastMissedPacket[device] = nil
    }

    func forget(_ device: String) {
        disconnect(device)
        entries[device] = nil
        defaults.removeObject(forKey: key(device))
    }

    private func key(_ device: String) -> String { "nearo_call_history_" + device }

    func record(_ packet: NetworkPacket, for device: String, at date: Date = .now) {
        guard let event = Event(rawValue: packet.string(for: "event") ?? "") else { return }
        let number = packet.string(for: "phoneNumber").flatMap { $0.isEmpty ? nil : $0 }
        let name = packet.string(for: "contactName").flatMap { $0.isEmpty ? nil : $0 }
        load(device)
        var calls = entries[device] ?? []
        let previous = pending[device]
        let activeIndex = previous.flatMap { active in calls.firstIndex { $0.id == active.entryID } }
        let activeNumber = activeIndex.flatMap { calls[$0].number }
        let sameCaller = number == nil || activeNumber == nil || activeNumber == number
        if packet.bool(for: "isCancel") {
            guard sameCaller, previous?.event == event else { return }
            if event == .ringing {
                // Some peers cancel the ring just before reporting its outcome.
                pending[device]?.cancelledAt = date
            } else {
                disconnect(device)
            }
            return
        }

        if event == .missedCall, lastMissedPacket[device] == packet.id { return }
        lastMissedPacket[device] = event == .missedCall ? packet.id : nil
        let index = sameCaller && previous?.continues(with: event, at: date) == true ? activeIndex : nil
        let kind: CallEntry.Kind
        switch event {
        case .ringing: kind = .incoming
        case .missedCall: kind = .missed
        case .talking:
            // "talking" alone carries no direction.
            kind = index.map { calls[$0].kind == .connected ? .connected : .answered } ?? .connected
        }

        let entryID: UUID
        if let index {
            entryID = calls[index].id
            calls[index].kind = kind
            if let name, name != number || calls[index].name == nil { calls[index].name = name }
            if let number { calls[index].number = number }
        } else {
            let call = CallEntry(date: date, kind: kind, number: number, name: name)
            entryID = call.id
            calls.insert(call, at: 0)
            if calls.count > Self.limit { calls.removeLast(calls.count - Self.limit) }
        }
        pending[device] = event == .missedCall ? nil : Pending(entryID: entryID, event: event)
        save(calls, for: device)
    }

    func mergePhoneHistory(_ snapshot: [CallEntry], for device: String) {
        load(device)
        var remaining = entries[device] ?? []
        var merged: [CallEntry] = []
        for var call in snapshot {
            // PBAP timestamps have second precision. Preserve the row identity on
            // repeated pulls and reconcile a matching, locally observed call once.
            let exact = remaining.firstIndex {
                $0.fromPhone == true && $0.date == call.date && $0.number == call.number && $0.kind == call.kind
            }
            let match = exact ?? remaining.indices.filter { index in
                let live = remaining[index]
                guard live.fromPhone != true, abs(live.date.timeIntervalSince(call.date)) <= 5 else { return false }
                let sameNumber = live.number == call.number ||
                    (live.number.flatMap(ContactBook.key) != nil && live.number.flatMap(ContactBook.key) == call.number.flatMap(ContactBook.key))
                return sameNumber && (live.kind == call.kind || live.kind == .incoming ||
                    live.kind == .connected || (live.kind == .answered && call.kind == .incoming))
            }.min { abs(remaining[$0].date.timeIntervalSince(call.date)) < abs(remaining[$1].date.timeIntervalSince(call.date)) }
            if let match {
                let previous = remaining.remove(at: match)
                call.id = previous.id
                if call.name == nil { call.name = previous.name }
            }
            merged.append(call)
        }
        merged += remaining.filter { $0.fromPhone != true }
        let newest = merged.sorted { $0.date > $1.date }.prefix(Self.limit)
        save(Array(newest), for: device)
    }

    private func save(_ calls: [CallEntry], for device: String) {
        guard calls != entries[device] else { return }
        if let data = try? JSONEncoder().encode(calls) { defaults.set(data, forKey: key(device)) }
        entries[device] = calls
    }
}
