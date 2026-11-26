import SwiftUI

// Control Center's grid has a 64-point unit and 12-point gutters.
// A two-unit pill spans 140 points, and its leading disc is inset 14 points.
struct MenuControl: View {
    @Environment(\.workspaceTheme) private var theme
    let title: String
    var icon: WorkspaceIcon?
    var system: String?
    var subtitle: String?
    var disclosure = false
    var compact = false
    let action: () -> Void
    @State private var hovered = false

    init(_ title: String, icon: WorkspaceIcon? = nil, system: String? = nil,
         subtitle: String? = nil, disclosure: Bool = false, compact: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.system = system
        self.subtitle = subtitle
        self.disclosure = disclosure
        self.compact = compact
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Group {
                    if let icon { icon.view(compact ? 25 : 21) }
                    else if let system { Image(systemName: system).font(.system(size: compact ? 23 : 19, weight: .semibold)) }
                }
                .foregroundStyle(compact ? Color.primary : theme.badgeInk)
                .frame(width: compact ? 64 : 36, height: compact ? 64 : 36)
                .background(compact ? .clear : Color.white, in: Circle())
                if !compact {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.system(size: 12.5, weight: .semibold)).lineLimit(subtitle == nil ? 2 : 1)
                        if let subtitle {
                            Text(subtitle).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.primary.opacity(0.72))
                        }
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.leading, compact ? 0 : 14)
            .padding(.trailing, compact ? 0 : (disclosure && hovered ? 16 : 10))
            .frame(width: compact ? 64 : nil, height: 64)
            .frame(maxWidth: compact ? 64 : .infinity, alignment: .leading)
            .overlay(alignment: .trailing) {
                if disclosure && hovered {
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary).padding(.trailing, 10)
                }
            }
        }
        .buttonStyle(MenuGlassStyle(hovered: hovered, radius: 32))
        .onHover { hovered = $0 }
        .accessibilityLabel(title)
        .help(title)
    }
}

struct MenuDeviceHeader: View {
    @Environment(\.workspaceTheme) private var theme
    let device: DeviceViewModel
    let openDevice: () -> Void
    let chooseDevice: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: openDevice) {
                Image(systemName: device.deviceType.systemImageName)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(theme.badgeInk)
                    .frame(width: 36, height: 36)
                    .background(.white, in: Circle())
                    .padding(.leading, 14).padding(.trailing, 5)
                    .frame(height: 64).contentShape(.rect)
            }
            .accessibilityLabel("Open " + device.name + " in Nearo")
            .help("Open " + device.name + " in Nearo")
            Button(action: chooseDevice) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name).font(.system(size: 13, weight: .semibold))
                        HStack(spacing: 6) {
                            ConnectionDot(connected: device.isConnected)
                            Text(device.isConnected ? "Connected" : device.statusLine)
                            if device.isConnected, let battery = device.batteryPercent {
                                Label("\(battery)%", systemImage: DeviceSymbols.battery(battery, charging: device.isCharging))
                            }
                            if device.isConnected, let network = device.networkType { Text(network) }
                            if device.isConnected && device.isViaTailscale {
                                Image(systemName: "point.3.connected.trianglepath.dotted").accessibilityLabel("Tailscale")
                            }
                        }
                        .font(.system(size: 11.5, weight: .medium)).foregroundStyle(.primary.opacity(0.72))
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        .opacity(hovered ? 1 : 0)
                }
                .padding(.leading, 5).padding(.trailing, 14)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .contentShape(.rect)
            }
            .onHover { hovered = $0 }
            .accessibilityLabel("Devices, " + device.name)
            .accessibilityValue(device.statusLine)
            .help("Switch device")
        }
        .buttonStyle(.plain)
        .glassPanel(radius: 32)
    }
}

struct MenuGlassStyle: ButtonStyle {
    var hovered: Bool
    var radius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let label = configuration.label
            .background(.primary.opacity(configuration.isPressed ? 0.13 : hovered ? 0.055 : 0), in: shape)
            .contentShape(shape)
        if #available(macOS 26, *) {
            label.glassEffect(.regular.interactive(), in: shape)
        } else {
            label.background(.regularMaterial, in: shape)
        }
    }
}

struct MenuDeviceRowStyle: ButtonStyle {
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 4)
            .background(.primary.opacity(configuration.isPressed ? 0.13 : hovered ? 0.07 : 0), in: .rect(cornerRadius: 8))
            .onHover { hovered = $0 }
    }
}

struct MenuDetailHeader: View {
    let title: String
    let back: () -> Void

    init(_ title: String, back: @escaping () -> Void) {
        self.title = title
        self.back = back
    }

    var body: some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .bold))
            Spacer()
            Button(action: back) {
                Image(systemName: "chevron.backward").frame(width: 26, height: 26).contentShape(.circle)
            }
                .accessibilityLabel("Back")
                .buttonStyle(.plain)
                .help("Back to Nearo controls")
        }
    }
}
