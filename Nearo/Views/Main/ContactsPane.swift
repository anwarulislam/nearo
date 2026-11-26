//
//  ContactsPane.swift
//  Nearo
//
//  Browse and search contacts synced from the connected phone.
//

import SwiftUI
import AppKit

struct ContactsPane: View {
    @Bindable var device: DeviceViewModel
    var onSelectSection: ((DeviceSection) -> Void)?

    var searchText = ""
    @State private var selectedContactId: String?
    @State private var copiedNumber: String?

    private var filteredContacts: [Contact] {
        device.contacts.searchContacts(searchText)
    }

    private var selectedContact: Contact? {
        if let selectedContactId {
            return device.contacts.contacts[selectedContactId] ?? filteredContacts.first { $0.id == selectedContactId }
        }
        return filteredContacts.first
    }

    var body: some View {
        if device.contacts.isEmpty {
            ContentUnavailableView {
                Label("No Contacts", systemImage: "person.crop.circle.badge.questionmark")
            } description: {
                Text("Contacts sync from \(device.name). Make sure KDE Connect has Contacts permission on your phone.")
            } actions: {
                if device.isConnected {
                    Button("Sync Contacts") { device.refreshContacts() }
                }
            }
            .task {
                if device.isConnected {
                    device.refreshContacts()
                }
            }
        } else {
            WorkspaceSplit {
                contactList
            } detail: {
                VStack(spacing: 0) {
                    HStack {
                        Text("Contact details").font(.headline)
                        Spacer()
                        if let number = selectedContact?.numbers.first {
                            Menu {
                                Button("Copy number") { copyToClipboard(number) }
                                Button("Open conversation") {
                                    device.startMessage(to: number, name: selectedContact?.name ?? number)
                                    onSelectSection?(.messages)
                                }.disabled(!device.isConnected)
                            } label: { WorkspaceIcon.more.view() }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .accessibilityLabel("Contact options")
                        }
                    }
                    .padding(.horizontal, 16).frame(height: 55).background { WorkspaceFrost(shape: Rectangle(), role: .toolbar) }
                    Divider()
                    contactDetail
                }
            }
            .onAppear {
                if selectedContactId == nil {
                    selectedContactId = filteredContacts.first?.id
                }
            }
            .onChange(of: searchText) {
                if let selectedContactId, !filteredContacts.contains(where: { $0.id == selectedContactId }) {
                    self.selectedContactId = filteredContacts.first?.id
                }
            }
        }
    }

    // MARK: - Left List

    private var contactList: some View {
        VStack(spacing: 0) {
            HStack {
                if searchText.isEmpty {
                    Text("\(device.contacts.count) \(device.contacts.count == 1 ? "contact" : "contacts")")
                } else {
                    Text("\(filteredContacts.count) \(filteredContacts.count == 1 ? "match" : "matches")")
                }
                Spacer()
                if device.isConnected {
                    WorkspaceIconButton(title: "Sync contacts", icon: .refresh) { device.refreshContacts() }
                }
            }
            .padding(.top, 8)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, WorkspaceSplitMetrics.listInset)
            .padding(.bottom, 6)

            if filteredContacts.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List(selection: $selectedContactId) {
                    ForEach(filteredContacts) { contact in
                        ContactRowView(contact: contact)
                            .workspaceListRow(selected: selectedContactId == contact.id)
                            .tag(contact.id)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
    }

    // MARK: - Right Detail

    @ViewBuilder
    private var contactDetail: some View {
        if let contact = selectedContact {
            ScrollView {
                VStack(spacing: 24) {
                    // Contact Header
                    VStack(spacing: 12) {
                        InitialsAvatar(name: contact.name, size: 80, photo: contact.photo)

                        VStack(spacing: 4) {
                            Text(contact.name)
                                .font(.title2.weight(.bold))
                                .multilineTextAlignment(.center)

                            if let primaryNumber = contact.numbers.first {
                                Text(primaryNumber)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }

                        // Top Action Buttons
                        if let primaryNumber = contact.numbers.first {
                            HStack(spacing: 12) {
                                Button {
                                    device.startMessage(to: primaryNumber, name: contact.name)
                                    onSelectSection?(.messages)
                                } label: {
                                    WorkspaceLabel("Message", .message)
                                }
                                .glassButton()
                                .disabled(!device.isConnected)

                                Button {
                                    copyToClipboard(primaryNumber)
                                } label: {
                                    WorkspaceLabel(copiedNumber == primaryNumber ? "Copied" : "Copy number",
                                                   copiedNumber == primaryNumber ? .check : .clipboard)
                                }
                                .glassButton()
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.top, 24)

                    // Phone numbers section
                    VStack(alignment: .leading, spacing: 10) {
                        PanelHeader("Phone Numbers")
                        VStack(spacing: 0) {
                            if contact.numbers.isEmpty {
                                Text("No phone numbers available")
                                    .foregroundStyle(.secondary)
                                    .glassRow()
                            } else {
                                ForEach(Array(contact.numbers.enumerated()), id: \.offset) { index, number in
                                    if index > 0 { Divider().padding(.leading, 16) }
                                    HStack(spacing: 12) {
                                        WorkspaceIcon.call.view()
                                            .foregroundStyle(.tint)
                                            .frame(width: 20)
                                        Text(number)
                                            .font(.body)
                                            .monospacedDigit()
                                        Spacer()
                                        Button {
                                            copyToClipboard(number)
                                        } label: {
                                            (copiedNumber == number ? WorkspaceIcon.check : .clipboard).view(14)
                                                .foregroundStyle(copiedNumber == number ? .green : .secondary)
                                        }
                                        .buttonStyle(.borderless)
                                        .help("Copy to clipboard")

                                        Button {
                                            device.startMessage(to: number, name: contact.name)
                                            onSelectSection?(.messages)
                                        } label: { WorkspaceLabel("Message", .message) }
                                        .disabled(!device.isConnected)
                                        .glassButton()
                                        .controlSize(.small)
                                    }
                                    .glassRow()
                                }
                            }
                        }
                        .workspaceCard()
                    }

                    // Email section
                    if !contact.emails.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            PanelHeader("Email")
                            VStack(spacing: 0) {
                                ForEach(Array(contact.emails.enumerated()), id: \.offset) { index, email in
                                    if index > 0 { Divider().padding(.leading, 16) }
                                    HStack(spacing: 12) {
                                        Image(systemName: "envelope.fill")
                                            .foregroundStyle(.tint)
                                            .frame(width: 20)
                                        Text(email)
                                            .font(.body)
                                        Spacer()
                                        Button {
                                            copyToClipboard(email)
                                        } label: {
                                            (copiedNumber == email ? WorkspaceIcon.check : .clipboard).view(14)
                                                .foregroundStyle(copiedNumber == email ? .green : .secondary)
                                        }
                                        .buttonStyle(.borderless)
                                        .help("Copy email")

                                        Button("Mail", systemImage: "arrow.up.right") {
                                            if let url = URL(string: "mailto:\(email)") {
                                                NSWorkspace.shared.open(url)
                                            }
                                        }
                                        .glassButton()
                                        .controlSize(.small)
                                    }
                                    .glassRow()
                                }
                            }
                            .workspaceCard()
                        }
                    }

                    // Footer
                    HStack {
                        Text("Synced from \(device.name)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if device.isConnected {
                            Button("Sync Contacts") { device.refreshContacts() }
                                .buttonStyle(.link)
                                .font(.footnote)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            }
        } else {
            ContentUnavailableView("No Contact Selected", systemImage: "person.crop.circle", description: Text("Select a contact to view details."))
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedNumber = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copiedNumber == text { copiedNumber = nil }
        }
    }
}

// MARK: - Row View

private struct ContactRowView: View {
    let contact: Contact

    var body: some View {
        HStack(spacing: 10) {
            InitialsAvatar(name: contact.name, size: 34, photo: contact.photo)

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if let number = contact.numbers.first {
                    Text(number)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                } else if let email = contact.emails.first {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}
