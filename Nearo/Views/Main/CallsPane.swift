import SwiftUI

struct CallsPane: View {
    let device: DeviceViewModel

    var searchText = ""

    private var filtered: [CallEntry] {
        guard !searchText.isEmpty else { return device.calls }
        return device.calls.filter { call in
            [call.caller(in: device.contacts), call.number ?? "", call.kind.label]
                .contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        GlassPage("Calls", subtitle: device.isSyncingCalls ? "Reading call history over Bluetooth…" :
                      device.callSyncMessage ?? "Recent calls on \(device.name)") {
            Button { device.onSyncCalls?(false) } label: { WorkspaceLabel("Sync calls", .refresh) }
                .glassButton().disabled(device.onSyncCalls == nil || device.isSyncingCalls)
        } content: {
            if device.calls.isEmpty {
                ContentUnavailableView {
                    WorkspaceLabel("No calls yet", .call)
                } description: {
                    Text("Allow contact and call history sharing for this Mac in your phone’s Bluetooth settings. KDE Connect also reports new calls while connected.")
                }
                .frame(maxWidth: .infinity).workspaceCard()
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(filtered) { call in
                        let caller = call.caller(in: device.contacts)
                        HStack(spacing: 12) {
                            WorkspaceIcon.call.view(19)
                                .foregroundStyle(call.kind == .missed ? Color.red : Color.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(caller).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                if let number = call.number, number != caller {
                                    Text("\(call.kind.label) · \(number)")
                                } else {
                                    Text(call.kind.label)
                                }
                            }
                            .font(.callout).foregroundStyle(.secondary)
                            Spacer()
                            Text(call.date, format: .dateTime.year().month().day().hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .textSelection(.enabled)
                        .padding(12).workspaceCard()
                    }
                }
            }
        }
        .task(id: device.status) { device.onSyncCalls?(true) }
    }
}
