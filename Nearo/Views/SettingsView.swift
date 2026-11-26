//
//  SettingsView.swift
//  Nearo
//

import SwiftUI
import UserNotifications

enum WorkspaceAppearance: String, CaseIterable {
    case system, light, dark

    var appKitAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum SettingsTab: String, CaseIterable {
    case general, themes, devices, files, permissions, about

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .themes: "paintpalette"
        case .devices: "iphone"
        case .files: "folder"
        case .permissions: "hand.raised"
        case .about: "info.circle"
        }
    }
}

public struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    private var webAccess: WebAccess?
    private var tab: Binding<SettingsTab>?
    @State private var localTab = SettingsTab.general

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    init(viewModel: SettingsViewModel, webAccess: WebAccess, tab: Binding<SettingsTab>) {
        self.viewModel = viewModel
        self.webAccess = webAccess
        self.tab = tab
    }

    public var body: some View {
        let selection = tab ?? $localTab
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) { tabButtons(selection) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 4) {
                    tabButtons(selection)
                }
            }
            .padding(4)
            .workspaceCard(radius: 14)
            .padding(.horizontal, 16).padding(.vertical, 12)
            Group {
                switch selection.wrappedValue {
                case .general: GeneralSettings(viewModel: viewModel, webAccess: webAccess)
                case .themes: ThemeSettings()
                case .devices: DevicesSettings(viewModel: viewModel)
                case .files: FilesSettings(viewModel: viewModel)
                case .permissions: PermissionsSettings(viewModel: viewModel)
                case .about: AboutSettings()
                }
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: 800)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { viewModel.refresh() }
    }

    private func tabButtons(_ selection: Binding<SettingsTab>) -> some View {
        ForEach(SettingsTab.allCases, id: \.self) { item in
            let selected = selection.wrappedValue == item
            Button { selection.wrappedValue = item } label: {
                VStack(spacing: 4) {
                    Image(systemName: item.symbol).font(.system(size: 17)).frame(height: 20)
                    Text(item.rawValue.capitalized).font(.caption).fixedSize()
                }
                .frame(width: 76, height: 48)
                .background(.tint.opacity(selected ? 0.16 : 0), in: .rect(cornerRadius: 10))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
}

private struct ThemeSettings: View {
    @AppStorage(WorkspaceTheme.key) private var theme = WorkspaceTheme.nearo
    @AppStorage("workspaceAppearance") private var appearance = WorkspaceAppearance.system

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Appearance", selection: $appearance) {
                    ForEach(WorkspaceAppearance.allCases, id: \.self) { choice in
                        Text(choice.rawValue.capitalized).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 144), spacing: 12)], spacing: 12) {
                    ForEach(WorkspaceTheme.allCases, id: \.self) { option in
                        let selected = theme == option
                        Button { theme = option } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 0) {
                                    option.color(.sidebar).frame(width: 30)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Capsule().fill(option.color(.accent)).frame(width: 36, height: 6)
                                        RoundedRectangle(cornerRadius: 4).fill(option.color(.panel)).frame(height: 16)
                                    }
                                    .padding(10)
                                }
                                .frame(height: 54)
                                .background(option.color(.background))
                                .clipShape(.rect(cornerRadius: 7))
                                HStack {
                                    Text(option.rawValue).font(.callout.weight(.medium))
                                    Spacer()
                                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
                                }
                            }
                            .padding(10).workspaceCard()
                            .overlay {
                                if selected { RoundedRectangle(cornerRadius: 10).strokeBorder(.tint, lineWidth: 2) }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.rawValue)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
            .padding(20)
        }
    }
}

// MARK: - Files

struct FilesSettings: View {
    @Bindable var viewModel: SettingsViewModel
    @Bindable private var files = PhoneFilesController.shared

    var body: some View {
        Form {
            Section {
                Toggle("Mount phones as drives", isOn: $files.isEnabled)
            } footer: {
                Text("While a paired phone is connected, it appears in Finder as a drive named after it. Files are read from the phone as you open them, so videos play right away.")
                    .foregroundStyle(.secondary)
            }

            if files.isEnabled {
                ForEach(viewModel.pairedDevices) { device in
                    PhoneFilesSection(deviceId: device.deviceId, name: device.deviceName, type: device.deviceType)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct PhoneFilesSection: View {
    let deviceId: String
    let name: String
    let type: DeviceType
    @Bindable private var files = PhoneFilesController.shared
    @State private var method: PhoneFilesMethod = .sftp
    @State private var address = ""

    var body: some View {
        Section {
            Picker("Access files using", selection: $method) {
                ForEach(PhoneFilesMethod.allCases) { Text($0.title).tag($0) }
            }
            .onChange(of: method) { files.setMethod(method, for: deviceId) }

            if method == .adb {
                TextField("Wireless debugging address", text: $address, prompt: Text("192.168.1.20:37123"))
                    .onChange(of: address) { files.setADBAddress(address, for: deviceId) }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Use the IP address and port shown in Developer options › Wireless debugging on the phone. The port changes when wireless debugging restarts; until you update it, Nearo uses KDE Connect instead.")
                    Text("ADB gives Nearo full access to the phone, and needs adb on this Mac (brew install android-platform-tools).")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                if !files.isADBInstalled {
                    Label("adb isn't installed.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
                if let problem = files.adbProblem[deviceId] {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }

            if let error = files.mountError[deviceId] {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Show in Finder") { files.showInFinder(deviceId) }
                    .disabled(!files.mountedDevices.contains(deviceId))
            }
        } header: {
            HStack(spacing: 8) {
                DeviceSymbol(type: type)
                Text(name)
            }
        }
        .onAppear {
            method = files.method(for: deviceId)
            address = files.adbAddress(for: deviceId)
        }
    }
}

// MARK: - About

/// Who made Nearo, shared with the app menu's About panel.
public enum NearoCredits {
    public static let author = "Anwarul Islam"
    public static let authorURL = URL(string: "https://github.com/anwarulislam")!
    public static let websiteURL = URL(string: "https://anwar.bd")!
    public static let sourceURL = URL(string: "https://github.com/anwarulislam/Nearo")!
    public static let issuesURL = URL(string: "https://github.com/anwarulislam/Nearo/issues")!

    public static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    /// Credits for the standard About panel.
    public static var aboutPanelCredits: NSAttributedString {
        let text = NSMutableAttributedString(
            string: "Nearo — Native macOS Companion for Android\nCreated by \(author)\n",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)]
        )
        text.append(NSAttributedString(
            string: "github.com/anwarulislam/Nearo • anwar.bd",
            attributes: [.link: sourceURL, .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
        ))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
        return text
    }

    public static func showAboutPanel() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: aboutPanelCredits])
    }
}

struct AboutSettings: View {
    @Bindable private var updates = UpdateController.shared

    var body: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                        .accessibilityHidden(true)
                    Text("Nearo")
                        .font(.title2.weight(.semibold))
                    Text(NearoCredits.version)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                Toggle("Check for updates automatically", isOn: $updates.checksAutomatically)
                LabeledContent {
                    Button("Check Now") { updates.checkForUpdates() }
                } label: {
                    Text("Software update")
                    Text(lastCheckedText)
                }
            }

            Section {
                LabeledContent("Author") {
                    Link(NearoCredits.author, destination: NearoCredits.authorURL)
                }
                LabeledContent("Website") {
                    Link("anwar.bd", destination: NearoCredits.websiteURL)
                }
                LabeledContent("Source Code") {
                    Link("github.com/anwarulislam/Nearo", destination: NearoCredits.sourceURL)
                }
                LabeledContent("Found a bug?") {
                    Link("Report an issue", destination: NearoCredits.issuesURL)
                }
            }

            Section {
                Text("Nearo is a lightweight, high-performance native macOS companion for Android built on the KDE Connect protocol. It is an independent open-source project and isn't affiliated with KDE.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    private var lastCheckedText: String {
        if let release = updates.availableRelease {
            return "Nearo \(release.version) is available."
        }
        guard let date = updates.lastChecked else { return "Not checked yet." }
        return "Last checked \(date.formatted(.relative(presentation: .named)))."
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Bindable var viewModel: SettingsViewModel
    var webAccess: WebAccess?
    @State private var name = ""
    @AppStorage(MotionPreference.key) private var reduceMotion = false
    @AppStorage(OneTimeCode.autoCopyKey) private var copyCodes = false
    @AppStorage(CallMediaPauser.settingKey) private var pauseMediaDuringCalls = true
    @AppStorage(CallCard.settingKey) private var showCallCard = true
    @AppStorage(AwayLock.settingKey) private var lockWhenPhoneLeaves = false

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .onSubmit { viewModel.saveDeviceName(name) }
                    .onAppear { name = viewModel.deviceName }
            } header: {
                Text("This Mac")
            } footer: {
                Text("Shown on your phone in KDE Connect. Press Return to save.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Open at Login", isOn: Binding(
                    get: { viewModel.launchAtLogin },
                    set: { viewModel.setLaunchAtLogin($0) }
                ))
                Toggle(isOn: $reduceMotion) {
                    Text("Reduce motion")
                    Text("Turns off Nearo's animations, such as the drop highlight and list changes.")
                }
                Toggle(isOn: $copyCodes) {
                    Text("Copy verification codes automatically")
                    Text("When a notification from your phone contains a sign-in code, Nearo puts it on the clipboard.")
                }
                Toggle(isOn: $showCallCard) {
                    Text("Show calls in a floating card")
                    Text("Incoming calls appear in a card at the top right that stays until the phone stops ringing, then becomes a small pill while you're on the call.")
                }
                Toggle(isOn: $pauseMediaDuringCalls) {
                    Text("Pause media during calls")
                    Text("Pauses what's playing on this Mac while your phone rings or you're on a call, and resumes it afterwards.")
                }
                Toggle(isOn: $lockWhenPhoneLeaves) {
                    Text("Lock this Mac when your phone leaves")
                    Text("Locks the screen when your phone has been disconnected for half a minute, such as when you walk away with it.")
                }
            }

            if let webAccess { WebAccessSettings(access: webAccess) }
            TailscaleSection(viewModel: viewModel)
            BluetoothSection(viewModel: viewModel)

            Section("Identity") {
                LabeledContent("Device ID") {
                    Text(viewModel.deviceId)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                }
                LabeledContent("Certificate") {
                    VStack(alignment: .trailing, spacing: 1) {
                        ForEach(FingerprintFormat.rows(viewModel.certificateFingerprint), id: \.self) { Text($0) }
                    }
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                }
                LabeledContent("Listening on", value: "Port \(viewModel.listeningPort)")
            }
        }
        .formStyle(.grouped)
    }
}

private struct WebAccessSettings: View {
    let access: WebAccess

    var body: some View {
        Section("Web access") {
            Toggle("Serve Nearo in a browser", isOn: Binding(get: { access.enabled }, set: access.setEnabled))
            if let link = access.link, let domain = access.domainAddress, let ip = access.ipAddress {
                if ip.port == 8765 {
                    Toggle("Use Apache for a portless address", isOn: Binding(
                        get: { access.usesApacheAddress || access.configuringApache },
                        set: { value in Task { await access.setUseApacheAddress(value) } }
                    ))
                    .disabled(access.configuringApache)
                    if access.configuringApache {
                        ProgressView("Checking nearo.local…").controlSize(.small)
                    } else if let problem = access.apacheProblem {
                        Text(problem).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    } else if !access.usesApacheAddress {
                        Text("Use http://nearo.local with this Mac’s Apache server. Installing the route requires administrator approval.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Domain", value: domain.absoluteString).textSelection(.enabled)
                LabeledContent("Loopback IP", value: ip.absoluteString).textSelection(.enabled)
                HStack {
                    Text("Available only on this Mac while Nearo is running.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Copy private link") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(link.absoluteString, forType: .string)
                    }
                    Link("Open in Browser", destination: link)
                }
            } else if let problem = access.problem {
                Text(problem).foregroundStyle(.secondary)
                Button("Retry") { access.setEnabled(true) }
            } else if access.enabled {
                ProgressView().controlSize(.small)
            }
        }
    }
}

// MARK: - Tailscale

private struct TailscaleSection: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Section {
            Toggle("Find devices over Tailscale", isOn: $viewModel.isTailscaleDiscoveryEnabled)
                .disabled(!isRunning)
            LabeledContent("Status") {
                Text(statusText)
                    .multilineTextAlignment(.trailing)
            }
        } header: {
            Text("Tailscale")
        } footer: {
            Text("Connects to your phone from anywhere when both devices are on your Tailscale network. Nearo only contacts Android and iOS devices signed in to your own Tailscale account.")
                .foregroundStyle(.secondary)
        }
    }

    private var isRunning: Bool {
        if case .running = viewModel.tailscaleStatus { return true }
        return false
    }

    private var statusText: String {
        switch viewModel.tailscaleStatus {
        case .notInstalled:
            return "Not installed"
        case .notRunning:
            return "Not connected"
        case .running(let selfIP, let phones):
            if phones.isEmpty { return "Connected as \(selfIP), no phones online" }
            return "Connected as \(selfIP) · \(phones.map(\.name).formatted(.list(type: .and)))"
        }
    }
}

// MARK: - Bluetooth (Beta)

private struct BluetoothSection: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Section {
            Toggle("Enable Bluetooth (Beta)", isOn: $viewModel.isBluetoothEnabled)
            LabeledContent("Status") {
                Text(viewModel.bluetoothStatusText)
                    .foregroundStyle(viewModel.isBluetoothEnabled ? .primary : .secondary)
            }
            if let address = viewModel.localBluetoothAddress {
                LabeledContent("Mac Bluetooth Address") {
                    Text(address)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            if viewModel.isBluetoothEnabled && !viewModel.pairedBluetoothDevices.isEmpty {
                DisclosureGroup("Paired Bluetooth Devices (\(viewModel.pairedBluetoothDevices.count))") {
                    ForEach(viewModel.pairedBluetoothDevices.sorted(by: { $0.key < $1.key }), id: \.key) { name, addr in
                        LabeledContent(name) {
                            Text(addr)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Bluetooth (Beta)")
        } footer: {
            Text("Connects to your phone over Bluetooth RFCOMM when Wi-Fi is unavailable. Keep disabled by default if Wi-Fi or Tailscale is preferred.")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Devices

private struct DevicesSettings: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var deviceToUnpair: PairedDevice?

    var body: some View {
        Form {
            if viewModel.pairedDevices.isEmpty {
                Section {
                    Text("No paired devices. Pair from KDE Connect on your phone, or from the Nearo window.")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(viewModel.pairedDevices) { device in
                Section {
                    Toggle("Share clipboard", isOn: Binding(
                        get: { device.isClipboardSyncEnabled },
                        set: { viewModel.setSync(deviceId: device.deviceId, clipboard: $0, notifications: device.isNotificationSyncEnabled) }
                    ))
                    Toggle("Show phone notifications", isOn: Binding(
                        get: { device.isNotificationSyncEnabled },
                        set: { viewModel.setSync(deviceId: device.deviceId, clipboard: device.isClipboardSyncEnabled, notifications: $0) }
                    ))
                    ReceiveFolderSetting(device: device)
                    LabeledContent("Paired", value: device.pairedDate.formatted(date: .abbreviated, time: .omitted))
                    if let lastSeen = device.lastSeenDate {
                        LabeledContent("Last connected", value: lastSeen.formatted(.relative(presentation: .named)))
                    }
                    if let bt = BluetoothService.shared.bluetoothAddress(forDeviceName: device.deviceName) {
                        LabeledContent("Bluetooth Address") {
                            Text(bt)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                } header: {
                    HStack(spacing: 8) {
                        DeviceSymbol(type: device.deviceType)
                        Text(device.deviceName)
                        Spacer()
                        Button("Unpair…", role: .destructive) { deviceToUnpair = device }
                            .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Unpair \(deviceToUnpair?.deviceName ?? "device")?",
            isPresented: Binding(get: { deviceToUnpair != nil }, set: { if !$0 { deviceToUnpair = nil } }),
            presenting: deviceToUnpair
        ) { device in
            Button("Unpair", role: .destructive) { viewModel.unpair(deviceId: device.deviceId) }
        } message: { device in
            Text("You'll need to pair again from \(device.deviceName) to reconnect.")
        }
    }
}

private struct ReceiveFolderSetting: View {
    let device: PairedDevice
    @AppStorage private var path: String?

    init(device: PairedDevice) {
        self.device = device
        _path = AppStorage(ReceiveFolder.preferenceKey(for: device.deviceId))
    }

    var body: some View {
        LabeledContent("Download folder") {
            let folder = path ?? ReceiveFolder.defaultURL.path
            Text((folder as NSString).abbreviatingWithTildeInPath)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(folder)
            Button("Choose…") {
                let panel = NSOpenPanel()
                panel.title = "Download folder for \(device.deviceName)"
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.canCreateDirectories = true
                panel.directoryURL = URL(fileURLWithPath: folder, isDirectory: true)
                if panel.runModal() == .OK, let selected = panel.url {
                    path = selected.path
                }
            }
            if path != nil {
                Button("Reset") { path = nil }
                    .help("Use the default Downloads folder")
            }
        }
    }
}

// MARK: - Permissions

private struct PermissionsSettings: View {
    @Bindable var viewModel: SettingsViewModel
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        Form {
            Section {
                PermissionRow(
                    title: "Notifications",
                    detail: "Show phone notifications and let you reply from banners.",
                    systemImage: "bell.badge",
                    state: notificationState
                ) {
                    if viewModel.notificationAuthStatus == .notDetermined {
                        Button("Allow") { viewModel.requestNotificationPermission() }
                    } else {
                        Button("Open Settings…") { viewModel.openNotificationSettings() }
                    }
                }

                PermissionRow(
                    title: "Accessibility",
                    detail: "Let your phone move the pointer, type and click as a remote trackpad and presenter.",
                    systemImage: "cursorarrow.motionlines",
                    state: viewModel.isAccessibilityTrusted ? .granted : .needed
                ) {
                    if !viewModel.isAccessibilityTrusted {
                        Button("Allow…") { viewModel.promptAccessibility() }
                    }
                }
            } footer: {
                Text("Nearo talks to your devices directly, over your local network or Tailscale. Nothing is sent to a server.")
                    .foregroundStyle(.secondary)
            }

            Section("Presenter") {
                LabeledContent("Laser pointer") {
                    Button("Show Test Pointer") {
                        PresenterOverlayWindowController.shared.update(xPos: 0.5, yPos: 0.5)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: controlActiveState) { viewModel.refresh() }
    }

    private var notificationState: PermissionState {
        switch viewModel.notificationAuthStatus {
        case .authorized, .provisional, .ephemeral: .granted
        case .denied: .denied
        default: .needed
        }
    }
}

private enum PermissionState { case granted, needed, denied }

private struct PermissionRow<Action: View>: View {
    let title: String
    let detail: String
    let systemImage: String
    let state: PermissionState
    @ViewBuilder var action: Action

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                    statusBadge
                }
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            action
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch state {
        case .granted:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Allowed")
        case .denied:
            Text("Off").font(.caption.weight(.medium)).foregroundStyle(.orange)
        case .needed:
            Text("Not allowed").font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
#Preview("Settings") {
    SettingsView(viewModel: .mock())
}

#Preview("Permissions needed") {
    SettingsView(viewModel: .mockDenied())
}

#Preview("About") {
    AboutSettings()
        .frame(width: 560, height: 460)
}
#endif
