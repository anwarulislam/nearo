import AppIntents
import SwiftUI
import WidgetKit

struct WidgetDeviceChoice: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Nearo Device")
    static let defaultQuery = WidgetDeviceQuery()
    static let current = Self(id: "current", name: "Follow Nearo")
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    init(id: String, name: String) { self.id = id; self.name = name }
    init(_ device: WidgetDeviceStatus) { self.init(id: "device:" + device.id, name: device.name) }
    var pinnedID: String? { id.hasPrefix("device:") ? String(id.dropFirst(7)) : nil }
}

struct WidgetDeviceQuery: EntityQuery {
    func suggestedEntities() async throws -> [WidgetDeviceChoice] {
        [.current] + (DeviceWidgetSnapshot.read()?.devices ?? []).map(WidgetDeviceChoice.init)
    }

    func entities(for identifiers: [String]) async throws -> [WidgetDeviceChoice] {
        let choices = try await suggestedEntities()
        return identifiers.compactMap { id in
            if let known = choices.first(where: { $0.id == id }) { return known }
            guard id.hasPrefix("device:") else { return nil }
            return WidgetDeviceChoice(id: id, name: "Unavailable device")
        }
    }

    func defaultResult() async -> WidgetDeviceChoice? { .current }
}

struct DeviceWidgetSettings: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Nearo Device"
    @Parameter(title: "Device") var device: WidgetDeviceChoice?
}

private struct DeviceEntry: TimelineEntry {
    let date: Date
    let device: WidgetDeviceStatus?
    let pinnedName: String?
    static let preview = Self(date: .now, device: WidgetDeviceStatus(id: "preview", name: "Pixel 10",
        symbol: "iphone", connected: true, battery: 68, charging: false, title: "Window Seat", artist: "June Atlas"), pinnedName: nil)
}

private struct DeviceProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DeviceEntry { .preview }

    func snapshot(for configuration: DeviceWidgetSettings, in context: Context) async -> DeviceEntry {
        let live = entry(configuration)
        return context.isPreview && live.device == nil && live.pinnedName == nil ? .preview : live
    }

    func timeline(for configuration: DeviceWidgetSettings, in context: Context) async -> Timeline<DeviceEntry> {
        Timeline(entries: [entry(configuration)], policy: .after(.now.addingTimeInterval(900)))
    }

    private func entry(_ configuration: DeviceWidgetSettings) -> DeviceEntry {
        let choice = configuration.device
        return DeviceEntry(date: .now, device: DeviceWidgetSnapshot.read()?.device(pinnedTo: choice?.pinnedID),
                           pinnedName: choice?.pinnedID == nil ? nil : choice?.name)
    }
}

private struct DeviceWidgetView: View {
    let entry: DeviceEntry
    @Environment(\.widgetFamily) private var family
    private var device: WidgetDeviceStatus? { entry.device }
    private var connected: Bool { device?.connected == true }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: device?.symbol ?? "iphone")
                    .font(.system(size: 29, weight: .medium)).foregroundStyle(.blue).widgetAccentable()
                Spacer(minLength: 5)
                Text(device?.name ?? entry.pinnedName ?? "Nearo").font(.headline).lineLimit(2)
                HStack(spacing: 5) {
                    Circle().fill(connected ? Color.green : .secondary).frame(width: 6, height: 6)
                    Text(connected ? "Connected" : entry.pinnedName == nil && device == nil ? "No device" : "Offline")
                }
                .font(.caption).foregroundStyle(.secondary)
                if connected, let battery = device?.battery {
                    Label("\(battery)%", systemImage: device?.charging == true ? "battery.100percent.bolt" :
                            "battery.\(min(100, max(0, Int((Double(battery) / 25).rounded()) * 25)))percent")
                        .font(.caption.weight(.medium))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if family == .systemMedium {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: "music.note").foregroundStyle(.secondary)
                    Spacer(minLength: 5)
                    Text(connected ? device?.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Not playing" : "No playback")
                        .font(.headline).lineLimit(2)
                    if connected, let artist = device?.artist, !artist.isEmpty {
                        Text(artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

@main
struct NearoDeviceWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: DeviceWidgetSnapshot.kind, intent: DeviceWidgetSettings.self, provider: DeviceProvider()) {
            DeviceWidgetView(entry: $0)
        }
        .configurationDisplayName("Device Status")
        .description("See connection, battery, and playback for a paired device.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#if DEBUG
#Preview("Device Status", as: .systemSmall) {
    NearoDeviceWidget()
} timeline: {
    DeviceEntry.preview
}

#Preview("Device Status and playback", as: .systemMedium) {
    NearoDeviceWidget()
} timeline: {
    DeviceEntry.preview
}
#endif
