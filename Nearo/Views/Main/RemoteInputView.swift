import SwiftUI

struct RemoteInputView: View {
    let device: DeviceViewModel
    @State private var capture = RemotePointerCapture()
    @State private var text = ""
    @State private var sendProblem: String?
    @FocusState private var editing: Bool
    @AppStorage(WorkspaceTheme.key) private var theme = WorkspaceTheme.nearo
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var available: Bool { device.isConnected && device.onRemoteInput != nil }

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 14) {
                Image(systemName: capture.isLocked ? "cursorarrow.motionlines" : "computermouse")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(theme.color(.accent))
                    .frame(width: 68, height: 68)
                    .background(theme.color(.accent).opacity(0.12), in: .circle)
                if available {
                    if capture.isLocked {
                        Text("Controlling " + device.name).font(.headline)
                        HStack(spacing: 8) {
                            Text("⌥ X").font(.headline.monospaced())
                                .padding(.horizontal, 9).padding(.vertical, 4)
                                .foregroundStyle(theme.color(.accent))
                                .background(theme.color(.accent).opacity(0.14), in: .rect(cornerRadius: 6))
                            Text("Unlock pointer").fontWeight(.medium)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Option X to unlock pointer")
                        Text("Or click the left and right mouse buttons together.")
                    } else {
                        Button("Lock pointer", systemImage: "lock") {
                            capture.start(isPhone: device.deviceType == .phone || device.deviceType == .tablet) {
                                _ = device.onRemoteInput?($0)
                            }
                            editing = capture.isLocked
                        }
                        Text(capture.error ?? "Move, click and scroll on your device with your Mac.")
                    }
                } else {
                    Text(device.isConnected ? "Enable remote input on your device in KDE Connect." : "Reconnect your device to resume control.")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .workspaceCard(radius: 16)

            HStack(spacing: 10) {
                Image(systemName: "keyboard").foregroundStyle(.secondary)
                TextField("Text to send", text: $text)
                    .textFieldStyle(.plain)
                    .focused($editing)
                    .onSubmit(sendText)
                Button("Send", systemImage: "arrow.up", action: sendText)
                    .disabled(text.isEmpty)
            }
            .padding(8)
            .padding(.leading, 5)
            .workspaceField()
            .disabled(!available)

            if let sendProblem {
                Text(sendProblem).font(.callout).foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                clickButton("Left click", command: "singleclick")
                clickButton("Middle click", command: "middleclick")
                clickButton("Right click", command: "rightclick")
            }
            .disabled(!available)
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 400)
        .toolbar {
            if #available(macOS 26, *) {
                titleItem.sharedBackgroundVisibility(.hidden)
                ToolbarSpacer(.flexible, placement: .primaryAction)
                deviceItem.sharedBackgroundVisibility(.hidden)
            } else {
                titleItem
                deviceItem
            }
        }
        .background(theme.color(.background).opacity(reduceTransparency ? 1 : 0.30))
        .background { if !reduceTransparency { WorkspaceBackdrop().ignoresSafeArea() } }
        .containerBackground(.clear, for: .window)
        .buttonStyle(RemoteInputButtonStyle())
        .environment(\.workspaceTheme, theme)
        .tint(theme.color(.accent))
        .onChange(of: available) { if !available { capture.stop() } }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) {
            capture.stop(ifWindow: $0.object as? NSWindow)
        }
        .onDisappear { capture.stop() }
    }

    private var titleItem: some ToolbarContent {
        ToolbarItem(placement: .navigation) { Text("Remote Input").font(.headline) }
    }

    private var deviceItem: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Label(device.name, systemImage: "iphone").labelStyle(.titleAndIcon)
                .padding(.trailing, 12)
                .foregroundStyle(.secondary)
        }
    }

    private func clickButton(_ title: String, command: String) -> some View {
        Button { _ = device.onRemoteInput?([command: true]) } label: {
            Text(title).frame(maxWidth: .infinity)
        }
    }

    private func sendText() {
        guard !text.isEmpty else { return }
        guard device.onRemoteInput?(["key": text]) == true else {
            sendProblem = "Reconnect your phone to send this text."
            return
        }
        sendProblem = nil
        text = ""
    }
}

private struct RemoteInputButtonStyle: ButtonStyle {
    @Environment(\.workspaceTheme) private var theme
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let accent = theme.color(.accent)
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(accent)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(accent.opacity(configuration.isPressed ? 0.24 : 0.10), in: .capsule)
            .overlay { Capsule().strokeBorder(accent.opacity(0.24)) }
            .contentShape(.capsule)
            .opacity(enabled ? 1 : 0.45)
    }
}
