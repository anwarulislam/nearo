//
//  CommandsPane.swift
//  Nearo
//
//  Shell commands the paired phone may run on this Mac.
//

import SwiftUI

struct CommandsPane: View {
    let device: DeviceViewModel
    @State private var editing: RemoteCommand?
    @State private var commandToDelete: RemoteCommand?
    @AppStorage(RunCommandPlugin.shortcutsKey) private var shareShortcuts = false

    var body: some View {
        GlassPage("Commands", subtitle: "Run commands on your Mac from \(device.name).") {
            Button {
                editing = RemoteCommand(name: "", command: "")
            } label: { WorkspaceLabel("Add Command…", .plus) }
            .buttonStyle(.borderedProminent)
        } content: {
            GlassSection("On this Mac", footer: "Commands run as your user account, so only add ones you trust.") {
                if device.commands.isEmpty {
                    Label("No commands yet.", systemImage: "terminal")
                        .foregroundStyle(.secondary)
                        .glassRow()
                } else {
                    ForEach(Array(device.commands.enumerated()), id: \.element.id) { index, command in
                        if index > 0 { Divider().padding(.leading, 16) }
                        row(for: command)
                            .glassRow()
                    }
                }
            }

            GlassSection("Shortcuts") {
                Toggle(isOn: $shareShortcuts) {
                    HStack(spacing: 10) {
                        WorkspaceIcon.grid.view().foregroundStyle(.white).frame(width: 30, height: 30)
                            .background(LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 7))
                        VStack(alignment: .leading) {
                            Text("Show my Mac shortcuts on the phone")
                            Text("Make shortcuts from the Shortcuts app available in Run Command.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: shareShortcuts) {
                    NearoService.shared.runCommandPlugin.refreshShortcuts()
                }
                .glassRow()
            }
        }
        .sheet(item: $editing) { command in
            CommandEditor(command: command) { device.saveCommand($0) }
        }
        .confirmationDialog(
            "Delete “\(commandToDelete?.name ?? "")”?",
            isPresented: Binding(get: { commandToDelete != nil }, set: { if !$0 { commandToDelete = nil } }),
            presenting: commandToDelete
        ) { command in
            Button("Delete", role: .destructive) { device.deleteCommand(id: command.id) }
        }
    }

    private func icon(for command: RemoteCommand) -> WorkspaceIcon {
        switch command.id {
        case "cmd_say_hello": .message
        case "cmd_sleep_display": .moon
        case "cmd_mute_audio": .volume
        default: .terminal
        }
    }

    private func row(for command: RemoteCommand) -> some View {
        HStack(spacing: 12) {
            icon(for: command).view(17).frame(width: 31, height: 31).workspaceField()
            VStack(alignment: .leading, spacing: 2) {
                Text(command.name)
                Text(command.command)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Run") { device.executeCommand(id: command.id) }
                .glassButton()
            Menu {
                Button("Edit…") { editing = command }
                Button("Duplicate") { device.saveCommand(RemoteCommand(name: command.name + " copy", command: command.command)) }
                Button("Delete…", role: .destructive) { commandToDelete = command }
            } label: {
                WorkspaceIcon.more.view()
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.borderless)
            .fixedSize()
            .accessibilityLabel("More for \(command.name)")
        }
        .contextMenu {
            Button("Run") { device.executeCommand(id: command.id) }
            Button("Edit…") { editing = command }
            Divider()
            Button("Delete…", role: .destructive) { commandToDelete = command }
        }
    }
}

private struct CommandEditor: View {
    @State var command: RemoteCommand
    let onSave: (RemoteCommand) -> Void
    @Environment(\.dismiss) private var dismiss

    private var isNew: Bool { command.name.isEmpty && command.command.isEmpty }
    private var canSave: Bool {
        !command.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !command.command.trimmingCharacters(in: .whitespaces).isEmpty
    }

    init(command: RemoteCommand, onSave: @escaping (RemoteCommand) -> Void) {
        _command = State(initialValue: command)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                TextField("Name", text: $command.name, prompt: Text("Sleep Display"))
                TextField("Command", text: $command.command, prompt: Text("pmset displaysleepnow"), axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(3...8)
            }
            .formStyle(.grouped)

            HStack {
                Text("Runs with /bin/sh")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(command)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 480)
        .navigationTitle(isNew ? "New Command" : "Edit Command")
    }
}

#if DEBUG
#Preview {
    CommandsPane(device: .mockConnectedPhone())
        .frame(width: 760, height: 480)
}
#endif
