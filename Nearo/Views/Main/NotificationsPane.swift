//
//  NotificationsPane.swift
//  Nearo
//

import SwiftUI

struct NotificationsPane: View {
    let device: DeviceViewModel

    var body: some View {
        GlassPage("Notifications", subtitle: "\(device.notifications.count) notifications on \(device.name)") {
            Button {
                for notification in device.notifications where notification.isDismissable {
                    device.dismiss(notification)
                }
            } label: { WorkspaceLabel("Clear all", .trash) }
            .glassButton()
            .disabled(!device.notifications.contains(where: \.isDismissable))
        } content: {
            if device.notifications.isEmpty {
                ContentUnavailableView {
                    WorkspaceLabel("You’re all caught up", .bell)
                } description: {
                    Text("New phone notifications will appear here.")
                }
                .frame(maxWidth: .infinity).workspaceCard()
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(device.notifications.sorted { $0.date > $1.date }) { notification in
                        NotificationRow(notification: notification, device: device).workspaceCard()
                    }
                }
            }
        }
    }
}

struct NotificationBadge: View {
    let item: PhoneNotification
    private var fallback: (WorkspaceIcon, Color) {
        switch item.appName.lowercased() {
        case "messages", "whatsapp": (.message, .green)
        case "pixel weather", "weather": (.sun, .blue)
        case "trip.com": (.plane, .blue)
        default: (.bell, .blue)
        }
    }

    var body: some View {
        Group {
            if let data = item.imageData, let image = NSImage(data: data) {
                if item.imageIsGlyph {
                    Image(nsImage: image).renderingMode(.template).resizable().scaledToFit()
                        .padding(6).foregroundStyle(.white).background(Color.blue.gradient)
                } else {
                    Image(nsImage: image).resizable().scaledToFit()
                }
            } else {
                fallback.0.view(19).foregroundStyle(.white)
                    .frame(width: 32, height: 32).background(fallback.1.gradient)
            }
        }
        .frame(width: 32, height: 32).clipShape(.rect(cornerRadius: 8))
        .accessibilityHidden(true)
    }
}

private struct NotificationRow: View {
    let notification: PhoneNotification
    let device: DeviceViewModel

    @State private var isReplying = false
    @State private var reply = ""
    @FocusState private var isReplyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 11) {
                NotificationBadge(item: notification)
                VStack(alignment: .leading, spacing: 3) {
                    Text(notification.appName).font(.caption).foregroundStyle(.secondary)
                    Text(notification.title).fontWeight(.semibold)
                    if !notification.text.isEmpty {
                        Text(notification.text).font(.callout).foregroundStyle(.secondary)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                Text(notification.date, format: .relative(presentation: .named))
                    .font(.caption2).foregroundStyle(.secondary)
            }

            if isReplying {
                HStack(spacing: 8) {
                    TextField("Reply to \(notification.title.isEmpty ? notification.appName : notification.title)", text: $reply)
                        .textFieldStyle(.roundedBorder)
                        .focused($isReplyFocused)
                        .onSubmit(sendReply)
                    Button("Cancel") { isReplying = false }
                        .keyboardShortcut(.cancelAction)
                    Button("Send", action: sendReply)
                        .keyboardShortcut(.defaultAction)
                        .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.top, 6)
                .onAppear { isReplyFocused = true }
            } else if notification.code != nil || notification.replyId != nil || notification.isDismissable {
                HStack(spacing: 16) {
                    if let code = notification.code {
                        CopyCodeButton(code: code)
                    }
                    if notification.replyId != nil {
                        Button("Reply") { isReplying = true }
                    }
                    if notification.isDismissable {
                        Button("Dismiss") { device.dismiss(notification) }
                    }
                }
                .buttonStyle(.link)
                .font(.callout)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .contextMenu {
            if let code = notification.code {
                Button("Copy Code \(code)") { NotificationPlugin.copyToPasteboard(code) }
            }
            if notification.replyId != nil {
                Button("Reply") { isReplying = true }
            }
            if notification.isDismissable {
                Button("Dismiss on Phone") { device.dismiss(notification) }
            }
            Button("Copy Text") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(notification.text, forType: .string)
            }
        }
    }

    private func sendReply() {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        device.reply(to: notification, text: text)
        reply = ""
        isReplying = false
    }
}

/// Copies a verification code and says so for a moment.
struct CopyCodeButton: View {
    let code: String
    @State private var copied = false

    var body: some View {
        Button {
            NotificationPlugin.copyToPasteboard(code)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Text(copied ? "Copied" : "Copy Code \(code)")
                .monospacedDigit()
        }
        .accessibilityLabel(copied ? "Copied" : "Copy code \(code.map(String.init).joined(separator: " "))")
    }
}

#if DEBUG
#Preview {
    NotificationsPane(device: .mockConnectedPhone())
        .frame(width: 640, height: 520)
}
#endif
