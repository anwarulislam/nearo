import SwiftUI
import AppKit

@Observable @MainActor
final class MenuNavigation {
    enum Page { case controls, devices, media }
    var page = Page.controls
}

public struct MenuBarView: View {
    @Bindable var appModel: NearoAppModel
    @Environment(\.openWindow) private var openWindow
    var onOpenMain: (() -> Void)?
    var onDismiss: (() -> Void)?
    @AppStorage(WorkspaceTheme.key) private var theme = WorkspaceTheme.nearo
    @State private var isDropTargeted = false

    var navigation = MenuNavigation()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let panelWidth: CGFloat = 308

    public init(appModel: NearoAppModel) {
        self.appModel = appModel
    }

    public var body: some View {
        VStack(spacing: 12) {
            if let request = appModel.incomingPairRequest { pairRequestCard(request) }
            switch navigation.page {
            case .controls: dashboard
            case .devices: devicesPanel
            case .media:
                if let device = appModel.primaryDevice {
                    MenuMediaDetail(device: device, back: { show(.controls) })
                        .id(device.id)
                }
            }
        }
        .environment(\.workspaceTheme, theme)
        .tint(theme.color(.accent))
        .padding(8)
        .frame(width: Self.panelWidth)
        .onExitCommand {
            if navigation.page == .controls { onDismiss?() } else { show(.controls) }
        }
        .onChange(of: appModel.primaryDevice?.id) {
            if navigation.page == .media { show(.controls) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let device = appModel.primaryDevice else { return false }
            let files = urls.filter(\.isFileURL)
            device.sendFiles(files)
            return !files.isEmpty
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted, let device = appModel.primaryDevice {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.tint, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .overlay {
                        Label("Send to \(device.name)", systemImage: "paperplane")
                            .font(.headline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: .capsule)
                    }
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Sections

    private func show(_ destination: MenuNavigation.Page) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { navigation.page = destination }
    }

    @ViewBuilder private var dashboard: some View {
        let primary = appModel.primaryDevice
        if let device = primary ?? appModel.offlineDevices.first {
            MenuDeviceHeader(device: device) {
                appModel.selectedDeviceId = device.id
                appModel.settingsTab = nil
                openMainWindow()
            } chooseDevice: { show(.devices) }
        } else {
            MenuControl("No Devices", icon: .phone, subtitle: "Open KDE Connect on your phone to pair.",
                        disclosure: true) { show(.devices) }
        }
        if let device = primary {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        MenuControl("Ring", icon: .ring, compact: true) { device.findMyPhone() }
                        MenuControl("Clipboard", icon: .clipboard, compact: true) { device.sendClipboard() }
                    }
                    MenuControl("Send Files", icon: .send) {
                        onDismiss?()
                        NSApp.activate()
                        device.sendFiles(FilePicker.chooseFiles(sendingTo: device.name))
                    }
                }
                MenuMediaTile(device: device) { show(.media) }
                    .frame(width: 140, height: 140)
            }
            if device.canLock {
                MenuControl("Lock", icon: .lock) { device.lockDevice() }
            }
        }
        if !appModel.availableDevices.isEmpty { nearbyCard }
        if let release = UpdateController.shared.availableRelease {
            MenuControl("Update to Nearo \(release.version)…", icon: .download) {
                onDismiss?()
                UpdateController.shared.showWindow()
            }
        }
        HStack(spacing: 12) {
            MenuControl("Open Nearo", icon: .monitor) { openMainWindow() }
            MenuControl("Settings", icon: .settings, compact: true) {
                appModel.settingsTab = .general
                openMainWindow()
            }
            MenuControl("Quit Nearo", system: "power", compact: true, action: NearoAppDelegate.quit)
        }
    }

    private var nearbyCard: some View {
        PopoverCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Nearby")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(appModel.availableDevices) { device in
                    HStack(spacing: 10) {
                        DeviceSymbol(type: device.deviceType, isActive: false)
                            .frame(width: 20)
                        Text(device.name)
                            .lineLimit(1)
                        Spacer()
                        if device.isAwaitingPairing {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Pair") { device.pair() }
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private var devicesPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuDetailHeader("Devices") { show(.controls) }
            Divider().padding(.vertical, 6)
            ForEach(appModel.allDevices) { device in
                let current = device.id == appModel.primaryDevice?.id
                Button {
                    switch device.status {
                    case .connected:
                        appModel.selectedDeviceId = device.id
                        show(.controls)
                    case .available: device.pair()
                    case .offline: break
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: device.deviceType.systemImageName)
                            .frame(width: 26, height: 26)
                            .background(current ? theme.color(.selection) : .secondary.opacity(0.18), in: Circle())
                            .foregroundStyle(current ? Color.white : .primary)
                        Text(device.name).lineLimit(1)
                        Spacer(minLength: 0)
                        if current { Image(systemName: "checkmark") }
                        else if device.isAwaitingPairing { ProgressView().controlSize(.small) }
                        else if device.status != .connected {
                            Text(device.status == .available ? "Pair" : "Offline").font(.caption)
                        }
                    }
                    .frame(height: 32)
                    .contentShape(.rect)
                }
                .buttonStyle(MenuDeviceRowStyle())
                .disabled(device.status == .offline || device.isAwaitingPairing)
                .accessibilityValue(current ? device.statusLine + ", selected" : device.statusLine)
                .help(device.statusLine)
            }
            if appModel.allDevices.isEmpty {
                Text("Open KDE Connect on your phone to pair.")
                    .foregroundStyle(.secondary).padding(.vertical, 8)
            }
            if let device = appModel.primaryDevice {
                let details = [device.batteryPercent.map { "\($0)% battery" }, device.networkType,
                               device.isViaTailscale ? "Tailscale" : nil].compactMap { $0 }
                if !details.isEmpty {
                    Divider().padding(.vertical, 6)
                    Text(details.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let link = appModel.webAccess.link {
                Divider().padding(.vertical, 6)
                Button {
                    onDismiss?()
                    NSWorkspace.shared.open(link)
                } label: {
                    HStack {
                        Image(systemName: "globe").foregroundStyle(theme.color(.accent))
                        Text("Open Nearo on Web").fontWeight(.medium)
                        Spacer()
                        Image(systemName: "arrow.up.right").imageScale(.small)
                    }
                    .foregroundStyle(.primary)
                    .frame(minHeight: 32)
                    .contentShape(.rect)
                }
                .buttonStyle(MenuDeviceRowStyle())
            }
        }
        .padding(14)
        .glassPanel(radius: 20)
    }

    private func pairRequestCard(_ request: PairRequestViewModel) -> some View {
        PopoverCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    DeviceSymbol(type: request.deviceType)
                        .font(.title2)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Pairing Request")
                            .font(.subheadline.weight(.semibold))
                        Text("\(request.deviceName) wants to pair")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button {
                        appModel.rejectIncomingPairRequest()
                    } label: {
                        Text("Decline").frame(maxWidth: .infinity)
                    }
                    Button {
                        appModel.acceptIncomingPairRequest(request)
                    } label: {
                        Text("Pair").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func openMainWindow() {
        if let onOpenMain { onOpenMain() } else { openWindow(id: "main") }
        NSApp.activate()
    }
}

// MARK: - Pieces

private struct PopoverCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(radius: 20)
    }
}

#if DEBUG
#Preview("Connected") {
    MenuBarView(appModel: .mock())
}

#Preview("Pair request") {
    MenuBarView(appModel: .mockPairRequest())
}

#Preview("Empty") {
    MenuBarView(appModel: .mockEmpty())
}
#endif
