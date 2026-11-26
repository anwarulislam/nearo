import AppKit
import SwiftUI

enum WorkspaceTheme: String, CaseIterable {
    case nearo = "Nearo", codex = "Codex", ayu = "Ayu", catppuccin = "Catppuccin", dracula = "Dracula"
    case everforest = "Everforest", github = "GitHub", gruvbox = "Gruvbox", linear = "Linear"
    case nord = "Nord", rosePine = "Rose Pine", solarized = "Solarized", tokyoNight = "Tokyo Night"

    static let key = "workspaceTheme"
    static var saved: Self { UserDefaults.standard.string(forKey: key).flatMap(Self.init(rawValue:)) ?? .nearo }

    // Each theme has a canvas and an accent for both appearances.
    private var seeds: (light: Int, lightAccent: Int, dark: Int, darkAccent: Int) {
        switch self {
        case .nearo:      (0xffffff, 0x007aff, 0x252527, 0x409cff)
        case .codex:      (0xfaf9f6, 0x53655f, 0x20211f, 0xa3c5b5)
        case .ayu:        (0xfaf8f3, 0x9a5a0c, 0x101720, 0xffb454)
        case .catppuccin: (0xeff1f5, 0x7354b6, 0x1e1e2e, 0xcba6f7)
        case .dracula:    (0xf4f0fa, 0x7547a6, 0x282a36, 0xbd93f9)
        case .everforest: (0xf4f1df, 0x536c35, 0x2d353b, 0xa7c080)
        case .github:     (0xffffff, 0x0969da, 0x0d1117, 0x58a6ff)
        case .gruvbox:    (0xfbf1c7, 0x974a11, 0x282828, 0xfabd2f)
        case .linear:     (0xf6f6fa, 0x5759ae, 0x19191e, 0xa3a2ec)
        case .nord:       (0xeceff4, 0x426282, 0x2e3440, 0x88c0d0)
        case .rosePine:   (0xfaf4ed, 0x925872, 0x191724, 0xebbcba)
        case .solarized:  (0xfdf6e3, 0x00726e, 0x002b36, 0x2aa198)
        case .tokyoNight: (0xe7eaf4, 0x34548a, 0x1a1b26, 0x7aa2f7)
        }
    }

    enum Role: String, CaseIterable {
        case background = "--bg", sidebar = "--side", toolbar = "--toolbar", panel = "--panel"
        case field = "--field", accent = "--blue", selection = "--blue-bg"
    }

    func rgb(_ role: Role, dark: Bool) -> Int {
        let base = dark ? seeds.dark : seeds.light
        let accent = dark ? seeds.darkAccent : seeds.lightAccent
        if role == .background { return base }
        if role == .accent { return accent }
        if role == .selection { return Self.mix(accent, 0, dark ? 0.48 : 0.18) }
        let amount: Double
        switch role {
        case .sidebar: amount = 0.065
        case .toolbar: amount = 0.035
        case .panel: amount = 0.085
        default: amount = 0.115
        }
        return Self.mix(base, dark ? 0xffffff : 0, amount)
    }

    private static func mix(_ a: Int, _ b: Int, _ fraction: Double) -> Int {
        [16, 8, 0].reduce(0) { result, shift in
            let start = Double((a >> shift) & 255), end = Double((b >> shift) & 255)
            return result | (Int((start + (end - start) * fraction).rounded()) << shift)
        }
    }

    func color(_ role: Role) -> Color {
        WorkspaceColor.adaptive(rgb(role, dark: false), rgb(role, dark: true))
    }

    // Menu icons sit on a white disc in both appearances.
    var badgeInk: Color { WorkspaceColor.adaptive(seeds.lightAccent, seeds.lightAccent) }

    var webColors: [String: [String: String]] {
        Dictionary(uniqueKeysWithValues: [false, true].map { dark in
            var colors = Dictionary(uniqueKeysWithValues: Role.allCases.map {
                ($0.rawValue, String(format: "#%06x", rgb($0, dark: dark)))
            })
            colors["--panel2"] = colors["--field"]
            return (dark ? "dark" : "light", colors)
        })
    }
}

extension EnvironmentValues {
    @Entry var workspaceTheme = WorkspaceTheme.nearo
}

struct WorkspacePaint: ShapeStyle {
    let role: WorkspaceTheme.Role
    func resolve(in environment: EnvironmentValues) -> Color { environment.workspaceTheme.color(role) }
}

/// Sample the desktop behind this window for the continuous frosted surface.
struct WorkspaceBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = WindowBlurView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private final class WindowBlurView: NSVisualEffectView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.isOpaque = false
        window?.backgroundColor = .clear
    }
}
