import SwiftUI

enum DeviceSection: String, CaseIterable, Identifiable {
    case overview, messages, calls, photos, contacts, notifications, files, commands

    var id: Self { self }
    var title: String { rawValue.capitalized }

    var searchPrompt: String? {
        switch self {
        case .contacts: "Search contacts"
        case .photos: "Search photos"
        case .messages: "Search conversations"
        case .calls: "Search calls"
        default: nil
        }
    }

    var icon: WorkspaceIcon {
        switch self {
        case .overview: .home
        case .messages: .message
        case .calls: .call
        case .photos: .image
        case .contacts: .users
        case .notifications: .bell
        case .files: .folder
        case .commands: .terminal
        }
    }

    func isAvailable(for device: DeviceViewModel) -> Bool {
        device.isConnected || self == .overview ||
            (self == .calls && device.status == .offline && (device.onSyncCalls != nil || !device.calls.isEmpty)) ||
            (self == .photos && !device.photos.isEmpty) ||
            (self == .contacts && !device.contacts.isEmpty)
    }
}

@Observable private final class WorkspaceNavigation {
    var section: DeviceSection
    var searchText = ""

    init(section: DeviceSection) { self.section = section }

    func visibleSection(for device: DeviceViewModel?) -> DeviceSection {
        guard let device, section.isAvailable(for: device) else { return .overview }
        return section
    }
}

public struct MainWindowView: View {
    @Bindable var appModel: NearoAppModel
    @State private var navigation: WorkspaceNavigation
    @State private var hidesSidebar = false
    @State private var compactSidebarOpen = false
    @State private var clipboardDevice: DeviceViewModel?
    @State private var deviceToUnpair: DeviceViewModel?
    @AppStorage(WorkspaceTheme.key) private var theme = WorkspaceTheme.nearo
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage(MotionPreference.key) private var reduceMotion = false
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(appModel: NearoAppModel) {
        self.init(appModel: appModel, initialSection: .overview)
    }

    init(appModel: NearoAppModel, initialSection: DeviceSection) {
        self.appModel = appModel
        _navigation = State(initialValue: WorkspaceNavigation(section: initialSection))
    }

    private var visibleSection: DeviceSection {
        navigation.visibleSection(for: appModel.selectedDevice)
    }

    public var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width <= 800
            let showsSidebar = compact ? compactSidebarOpen : !hidesSidebar
            let sidebarAnimation: Animation? = systemReduceMotion || reduceMotion ? nil : .easeInOut(duration: 0.22)
            let sidebarWidth: CGFloat = geometry.size.width <= 1100 ? 210 : 222
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    if !compact {
                        sidebar.frame(width: sidebarWidth)
                            .offset(x: showsSidebar ? 0 : -sidebarWidth)
                            .frame(width: showsSidebar ? sidebarWidth : 0, alignment: .leading)
                            .allowsHitTesting(showsSidebar)
                            .accessibilityHidden(!showsSidebar)
                    }
                    detail
                        .environment(\.isCompactWorkspace, compact)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(theme.color(.background).opacity(reduceTransparency ? 1 : 0.24))
                }
                if compact && showsSidebar {
                    Color.black.opacity(0.18).onTapGesture { compactSidebarOpen = false }
                    sidebar.frame(width: 222).transition(.move(edge: .leading))
                }
            }
            .animation(sidebarAnimation, value: showsSidebar)
            .toolbar {
                let columnLeading = !compact && showsSidebar ? sidebarWidth : 0
                WorkspaceWindowControls(appModel: appModel, navigation: navigation,
                                        showsSidebar: showsSidebar, columnLeading: columnLeading,
                                        sidebarAnimation: sidebarAnimation,
                                        clipboard: { clipboardDevice = $0 }, settings: settings) {
                    if compact { compactSidebarOpen.toggle() } else { hidesSidebar.toggle() }
                }
            }
        }
        .background { if !reduceTransparency { WorkspaceBackdrop().ignoresSafeArea() } }
        .containerBackground(.clear, for: .window)
        .frame(minWidth: 760, minHeight: 520)
        .sheet(item: $clipboardDevice) { ClipboardSheet(device: $0) }
        .sheet(isPresented: $appModel.isShowingConnectByIP) {
            ConnectByIPSheet { await appModel.addManualPeer(address: $0) }
        }
        .sheet(item: Binding(get: { appModel.incomingPairRequest }, set: { _ in })) { request in
            PairRequestSheet(request: request, onAccept: { appModel.acceptIncomingPairRequest(request) },
                             onDecline: { appModel.rejectIncomingPairRequest() })
        }
        .confirmationDialog("Unpair \(deviceToUnpair?.name ?? "device")?",
                            isPresented: Binding(get: { deviceToUnpair != nil }, set: { if !$0 { deviceToUnpair = nil } }),
                            presenting: deviceToUnpair) { device in
            Button("Unpair", role: .destructive) { device.unpair() }
        } message: { device in
            Text("You'll need to pair again from \(device.name) to reconnect.")
        }
        .environment(\.workspaceTheme, theme)
        .tint(theme.color(.accent))
        .onAppear {
            appModel.checkNotificationStatus()
            AppPresence.windowDidAppear()
        }
        .onDisappear { AppPresence.windowDidDisappear() }
        .onChange(of: appModel.selectedDeviceId) { navigation.section = .overview; navigation.searchText = "" }
    }

    @ViewBuilder private var detail: some View {
        ZStack {
            devicePage
                .opacity(appModel.settingsTab == nil ? 1 : 0)
                .disabled(appModel.settingsTab != nil)
                .accessibilityHidden(appModel.settingsTab != nil)
            if let tab = appModel.settingsTab {
                SettingsView(viewModel: appModel.settingsModel, webAccess: appModel.webAccess, tab: Binding(get: { appModel.settingsTab ?? tab },
                                                                            set: { appModel.settingsTab = $0 }))
            }
        }
    }

    @ViewBuilder private var devicePage: some View {
        @Bindable var navigation = navigation
        if let device = appModel.selectedDevice {
            DeviceDetailView(device: device, appModel: appModel, section: visibleSection, searchText: $navigation.searchText,
                             onSelectSection: select, onConnectByIP: connect, onClipboard: { clipboardDevice = device })
                .onChange(of: visibleSection) { navigation.searchText = "" }
                .id(device.id)
        } else if appModel.allDevices.isEmpty {
            OnboardingView(appModel: appModel, onConnectByIP: connect)
        } else {
            ContentUnavailableView("No Device Selected", systemImage: "iphone",
                                   description: Text("Choose a device in the sidebar."))
        }
    }

    private func select(_ destination: DeviceSection) {
        navigation.section = destination
        appModel.settingsTab = nil
        compactSidebarOpen = false
    }

    private func connect() {
        compactSidebarOpen = false
        appModel.isShowingConnectByIP = true
    }

    private func settings() {
        appModel.settingsTab = .general
        compactSidebarOpen = false
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    deviceGroup("My devices", devices: appModel.pairedDevices)
                    if !appModel.availableDevices.isEmpty {
                        deviceGroup("Nearby", devices: appModel.availableDevices)
                    }
                    if let device = appModel.selectedDevice, device.status != .available {
                        sidebarHeading(device.name).padding(.top, 18)
                        ForEach(DeviceSection.allCases) { destination in
                            sidebarButton(destination.title, icon: destination.icon,
                                          active: appModel.settingsTab == nil && visibleSection == destination,
                                          count: destination == .notifications ? device.notifications.count : 0) {
                                select(destination)
                            }
                            .disabled(!destination.isAvailable(for: device))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider().padding(.vertical, 7)
            sidebarButton("Connect a device", icon: .plus, footer: true, action: connect)
            sidebarButton("Settings", icon: .settings, active: appModel.settingsTab != nil, footer: true, action: settings)
        }
        .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 12)
        .background(theme.color(.sidebar).opacity(reduceTransparency || compactSidebarOpen ? 1 : 0.23))
        .overlay(alignment: .trailing) {
            Rectangle().fill(.separator)
                .frame(width: 1 / displayScale)
                .ignoresSafeArea(.container, edges: .vertical)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func sidebarHeading(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 9).padding(.bottom, 3)
    }

    private func deviceGroup(_ title: String, devices: [DeviceViewModel]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            sidebarHeading(title)
            ForEach(devices) { device in
                let selected = device.id == appModel.selectedDeviceId
                Button {
                    appModel.selectedDeviceId = device.id
                    select(.overview)
                } label: {
                    HStack(spacing: 8) {
                        Group {
                            if device.deviceType == .phone { WorkspaceIcon.phone.view(22) }
                            else if device.deviceType == .desktop || device.deviceType == .laptop { WorkspaceIcon.monitor.view(22) }
                            else { Image(systemName: device.deviceType.systemImageName) }
                        }
                        .frame(width: 27).foregroundStyle(selected ? theme.color(.accent) : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name).fontWeight(.medium)
                            HStack(spacing: 4) {
                                ConnectionDot(connected: device.isConnected)
                                Text(device.statusLine).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        if selected { WorkspaceSelectionCheck() }
                    }
                    .lineLimit(1).padding(.horizontal, 8).frame(height: 47)
                    .workspaceSelection(selected)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if device.isConnected {
                        Button("Ring Phone") { device.findMyPhone() }
                        Button("Send Files…") { device.sendFiles(FilePicker.chooseFiles(sendingTo: device.name)) }
                        if device.canLock { Button { device.lockDevice() } label: { WorkspaceLabel("Lock", .lock) } }
                    }
                    if device.status != .available {
                        Button("Unpair…", role: .destructive) { deviceToUnpair = device }
                    }
                }
            }
        }
    }

    private func sidebarButton(_ title: String, icon: WorkspaceIcon, active: Bool = false,
                               footer: Bool = false, count: Int = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                icon.view().foregroundStyle(footer && !active ? Color.secondary : theme.color(.accent))
                Text(title).fontWeight(active ? .semibold : .regular)
                Spacer()
                if count > 0 { Text(count, format: .number).font(.caption) }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 9).frame(height: 31)
            .background(active ? Color.primary.opacity(0.07) : .clear, in: .rect(cornerRadius: 6))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

}

// Keep the toolbar declaration independent of the current section. The title and
// search field observe navigation inside their existing toolbar items.
private struct WorkspaceWindowControls: ToolbarContent {
    let appModel: NearoAppModel
    let navigation: WorkspaceNavigation
    let showsSidebar: Bool
    let columnLeading: CGFloat
    let sidebarAnimation: Animation?
    let clipboard: (DeviceViewModel) -> Void
    let settings: () -> Void
    let toggleSidebar: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button(action: toggleSidebar) {
                Label { Text(showsSidebar ? "Hide sidebar" : "Show sidebar") } icon: { WorkspaceIcon.sidebar.view(17) }
            }
            .help(showsSidebar ? "Hide sidebar" : "Show sidebar")
            if appModel.settingsTab != nil {
                Button("Back", systemImage: "chevron.backward") { appModel.settingsTab = nil }
                    .help("Back")
            }
        }
        if #available(macOS 26, *) {
            titleItem.sharedBackgroundVisibility(.hidden)
            ToolbarSpacer(.flexible, placement: .primaryAction)
            actionsItem.sharedBackgroundVisibility(.hidden)
        } else {
            titleItem
            actionsItem
        }
    }

    private var titleItem: some ToolbarContent {
        ToolbarItem(id: "workspace-title", placement: .navigation) {
            GeometryReader { geometry in
                let itemLeading = geometry.frame(in: .global).minX
                WorkspaceSectionLabel(appModel: appModel, navigation: navigation)
                    .padding(.leading, max(4, columnLeading + WorkspaceSplitMetrics.listInset - itemLeading))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .animation(sidebarAnimation, value: columnLeading)
            }
            .frame(width: 222, height: 36)
        }
    }

    private var actionsItem: some ToolbarContent {
        ToolbarItem(id: "workspace-actions", placement: .primaryAction) {
            WorkspaceToolbarActions(appModel: appModel, navigation: navigation, clipboard: clipboard, settings: settings)
        }
    }
}

private struct WorkspaceSectionLabel: View {
    let appModel: NearoAppModel
    let navigation: WorkspaceNavigation

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(appModel.settingsTab != nil ? "Settings" : appModel.selectedDevice == nil ? "Devices" :
                    navigation.visibleSection(for: appModel.selectedDevice).title)
                .font(.headline)
            if appModel.settingsTab == nil, let device = appModel.selectedDevice {
                HStack(spacing: 5) {
                    ConnectionDot(connected: device.isConnected)
                    Text(device.name)
                }
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityLabel("\(device.name), \(device.status.rawValue)")
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct WorkspaceToolbarActions: View {
    let appModel: NearoAppModel
    @Bindable var navigation: WorkspaceNavigation
    let clipboard: (DeviceViewModel) -> Void
    let settings: () -> Void

    var body: some View {
        let device = appModel.selectedDevice
        let inSettings = appModel.settingsTab != nil
        let prompt = inSettings ? nil : navigation.visibleSection(for: device).searchPrompt
        HStack(spacing: 8) {
            ZStack {
                if let prompt {
                    WorkspaceSearch(placeholder: prompt, query: $navigation.searchText)
                }
            }
            .frame(width: 180, height: WorkspaceSearch.toolbarHeight)
            HStack(spacing: 0) {
                if let device {
                    Group {
                        button("Ring phone", .ring) { device.findMyPhone() }
                        button("Share clipboard", .clipboard) { clipboard(device) }
                        button("Send files", .send) { device.sendFiles(FilePicker.chooseFiles(sendingTo: device.name)) }
                    }
                    .disabled(!device.isConnected)
                }
                button("Settings", .settings, action: settings)
            }
            .glassCapsule()
        }
        .opacity(inSettings ? 0 : 1)
        .disabled(inSettings)
        .allowsHitTesting(!inSettings)
        .accessibilityHidden(inSettings)
        .transaction { $0.animation = nil }
    }

    private func button(_ title: String, _ icon: WorkspaceIcon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            icon.view(17).frame(width: WorkspaceSearch.toolbarHeight, height: WorkspaceSearch.toolbarHeight).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .help(title)
    }
}

// MARK: - Menu commands

public struct NearoCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    let appModel: NearoAppModel

    public init(appModel: NearoAppModel) {
        self.appModel = appModel
    }

    public var body: some Commands {
        CommandGroup(replacing: .appTermination) {
            Button("Quit Nearo", action: NearoAppDelegate.quit).keyboardShortcut("q")
        }
        CommandGroup(replacing: .appInfo) {
            Button("About Nearo") { NearoCredits.showAboutPanel() }
            Button("Check for Updates…") { UpdateController.shared.checkForUpdates() }
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                appModel.settingsTab = .general
                openWindow(id: "main")
                NSApp.activate()
            }
            .keyboardShortcut(",")
        }

        CommandGroup(after: .newItem) {
            Button("Connect by Address…") {
                openWindow(id: "main")
                appModel.isShowingConnectByIP = true
            }
            .keyboardShortcut("k")

            Button("Look for Devices") { appModel.refreshDiscovery() }
                .keyboardShortcut("r")
        }

        CommandMenu("Device") {
            let device = appModel.primaryDevice
            Button("Send Files…") {
                if let device { device.sendFiles(FilePicker.chooseFiles(sendingTo: device.name)) }
            }
            .keyboardShortcut("o")
            .disabled(device == nil)

            Button("Send Clipboard") { device?.sendClipboard() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(device == nil)

            Divider()

            Button("Ring Phone") { device?.findMyPhone() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(device == nil)

            if device?.canLock == true {
                Button("Lock") { device?.lockDevice() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
            }

            Button("Ping") { device?.ping() }
                .disabled(device == nil)
        }
    }
}

