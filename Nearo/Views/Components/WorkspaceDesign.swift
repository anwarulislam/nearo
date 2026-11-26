import SwiftUI

extension EnvironmentValues {
    @Entry var isCompactWorkspace = false
}

/// Template vectors from the Nearo interface draft, in its original 24-point grid.
enum WorkspaceIcon: String {
    case nearby, sidebar, phone, home, message, image, users, bell, folder, terminal
    case settings, plus, check, chevron, wifi, battery, signal, ring, clipboard, send
    case upload, download, drive, shield, search, refresh, edit, more, close, call
    case file, moon, lock, trash, grid, monitor, volume, sun, plane

    func view(_ size: CGFloat = 17) -> some View {
        Image("nr-" + rawValue)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

enum WorkspaceColor {
    static let green = adaptive(0x259b42, 0x32d74b)
    static let hairline = Color.primary.opacity(0.08)

    static func adaptive(_ light: Int, _ dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat(rgb >> 16) / 255,
                           green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        })
    }
}

struct WorkspaceFrost<Surface: Shape>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: Surface
    let role: WorkspaceTheme.Role

    var body: some View {
        ZStack {
            if !reduceTransparency {
                shape.fill(.ultraThinMaterial).opacity(0.55)
            }
            shape.fill(WorkspacePaint(role: role)).opacity(reduceTransparency ? 1 : 0.22)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    func workspaceCard(radius: CGFloat = 10) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        return background { WorkspaceFrost(shape: shape, role: .panel) }
            .overlay { shape.strokeBorder(WorkspaceColor.hairline).allowsHitTesting(false) }
    }

    func workspaceSelection(_ selected: Bool) -> some View {
        background(selected ? Color.primary.opacity(0.06) : .clear, in: .rect(cornerRadius: 7))
    }

    func workspaceListRow(selected: Bool = false) -> some View {
        HStack(spacing: 4) {
            self.frame(maxWidth: .infinity, alignment: .leading)
            if selected { WorkspaceSelectionCheck() }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .foregroundStyle(Color.primary)
        .workspaceSelection(selected)
        .background { if selected { ThemedListSelection() } }
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
    }

    func workspaceField() -> some View {
        let shape = RoundedRectangle(cornerRadius: 7)
        return background { WorkspaceFrost(shape: shape, role: .field) }
            .overlay { shape.strokeBorder(WorkspaceColor.hairline).allowsHitTesting(false) }
    }
}

struct WorkspaceSelectionCheck: View {
    var body: some View {
        WorkspaceIcon.check.view(13).foregroundStyle(WorkspacePaint(role: .accent))
    }
}

/// Keep native List keyboard navigation and accessibility while the row paints
/// its own theme color, including when focus moves to the toolbar search field.
private struct ThemedListSelection: NSViewRepresentable {
    final class Marker: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            var ancestor = superview
            while let view = ancestor {
                if let table = view as? NSTableView {
                    table.selectionHighlightStyle = .none
                    break
                }
                ancestor = view.superview
            }
        }
    }

    func makeNSView(context: Context) -> Marker { Marker() }
    func updateNSView(_ nsView: Marker, context: Context) {}
}

struct WorkspaceIconButton: View {
    let title: String
    let icon: WorkspaceIcon
    var size: CGFloat = 19
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            icon.view(size)
        }
        .glassButton()
        .buttonBorderShape(.circle)
        .frame(width: 30, height: 28)
        .foregroundStyle(.secondary)
        .accessibilityLabel(title)
        .help(title)
    }
}

struct ConnectionDot: View {
    let connected: Bool
    var body: some View {
        Circle().fill(connected ? WorkspaceColor.green : .gray)
            .frame(width: 6, height: 6)
            .accessibilityHidden(true)
    }
}

struct WorkspaceLabel: View {
    let title: String
    let icon: WorkspaceIcon

    init(_ title: String, _ icon: WorkspaceIcon) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 5) { icon.view(14); Text(title) }
    }
}

enum WorkspaceSplitMetrics {
    static let listInset: CGFloat = 16
}

struct WorkspaceSplit<ListContent: View, Detail: View>: View {
    @ViewBuilder var list: ListContent
    @ViewBuilder var detail: Detail

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                list.frame(width: geometry.size.width < 900 ? 240 : 278)
                    .background { WorkspaceFrost(shape: Rectangle(), role: .toolbar) }
                Divider()
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct WorkspaceSearch: View {
    @Environment(\.workspaceTheme) private var theme
    let placeholder: String
    @Binding var query: String
    @FocusState private var focused: Bool

    static var toolbarHeight: CGFloat {
        if #available(macOS 26, *) { return 36 }
        return 28
    }

    var body: some View {
        HStack(spacing: 6) {
            WorkspaceIcon.search.view(14).accessibilityHidden(true)
            TextField(placeholder, text: $query).textFieldStyle(.plain).focused($focused)
                .accessibilityLabel(placeholder)
                .foregroundStyle(.primary)
            if !query.isEmpty {
                Button { query = "" } label: { WorkspaceIcon.close.view(12) }
                    .buttonStyle(.borderless).accessibilityLabel("Clear search")
            }
        }
        .foregroundStyle(theme.color(.accent)).padding(.horizontal, 12).frame(height: Self.toolbarHeight)
        .background(theme.color(.field).opacity(0.32), in: Capsule())
        .glassCapsule()
        .overlay { Capsule().strokeBorder(theme.color(.accent).opacity(focused ? 0.7 : 0.2)) }
    }
}

struct WorkspaceBrand: View {
    var size: CGFloat = 26
    var body: some View {
        WorkspaceIcon.nearby.view(size * 0.7).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [Color(red: 0.44, green: 0.73, blue: 1),
                                                 Color(red: 0, green: 0.48, blue: 1),
                                                 Color(red: 0, green: 0.38, blue: 0.84)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: .rect(cornerRadius: size * 0.27))
            .accessibilityHidden(true)
    }
}

struct ClipboardSheet: View {
    let device: DeviceViewModel
    @State private var couldNotSend = false
    @State private var text = NSPasteboard.general.string(forType: .string) ?? ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Share clipboard").font(.title3.weight(.semibold))
            Text("Send text from your Mac to " + device.name + ".").foregroundStyle(.secondary)
            TextEditor(text: $text).font(.body)
                .scrollContentBackground(.hidden)
                .padding(7).workspaceField().frame(height: 100)
                .accessibilityLabel("Text to share")
            if couldNotSend {
                Text("Check the connection and enable Share clipboard in Device Settings.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Send to phone") {
                    if device.shareClipboardText(text) { dismiss() } else { couldNotSend = true }
                }.keyboardShortcut(.defaultAction).disabled(text.isEmpty || !device.isConnected)
            }
        }
        .padding(21).frame(width: 400)
    }
}
