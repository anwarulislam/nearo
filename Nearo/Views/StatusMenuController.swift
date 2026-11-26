import AppKit
import SwiftUI

/// A borderless status-item panel lets each Liquid Glass control sample the desktop.
@MainActor
final class StatusMenuController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let model: NearoAppModel
    private let openMain: () -> Void
    private let navigation = MenuNavigation()
    private var panel: NSPanel?
    private var outsideClick: Any?
    private var localEvent: Any?

    init(model: NearoAppModel, openMain: @escaping () -> Void) {
        self.model = model
        self.openMain = openMain
        super.init()
        item.button?.target = self
        item.button?.action = #selector(toggle)
        item.button?.toolTip = "Nearo"
        item.button?.setAccessibilityLabel("Nearo")
        updateIcon()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(dismiss),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }

    private func updateIcon() {
        let name = withObservationTracking { model.statusMenuBarSystemImageName } onChange: { [weak self] in
            Task { @MainActor in self?.updateIcon() }
        }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Nearo")
        image?.isTemplate = true
        item.button?.image = image
    }

    @objc private func toggle() {
        if panel != nil { dismiss(); return }
        _ = show(.controls)
    }

    func show(_ page: MenuNavigation.Page) -> Bool {
        guard let button = item.button, let screen = button.window?.screen else { return false }
        navigation.page = page
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return true
        }
        let panel = StatusPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        panel.setAccessibilityLabel("Nearo controls")
        self.panel = panel
        var controls = MenuBarView(appModel: model)
        let navigation = self.navigation
        controls.navigation = navigation
        controls.onDismiss = { [weak self] in self?.dismiss() }
        controls.onOpenMain = { [weak self] in
            self?.dismiss()
            self?.openMain()
        }
        let content = ViewThatFits(in: .vertical) {
            controls.fixedSize()
            ScrollView { controls }.frame(height: screen.visibleFrame.height - 12)
        }
        .frame(width: MenuBarView.panelWidth)
        .frame(maxHeight: screen.visibleFrame.height - 12)
        .fixedSize(horizontal: true, vertical: true)
        .nearoMotionPreference()
        .onGeometryChange(for: CGSize.self, of: { $0.size }) { [weak self, weak panel] size in
            guard let self, let panel, self.panel === panel else { return }
            self.position(panel, size: size)
        }
        let host = NSHostingView(rootView: content)
        panel.contentView = host
        position(panel, size: host.fittingSize)
        button.highlight(true)
        panel.makeKeyAndOrderFront(nil)

        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
        localEvent = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 {
                    if navigation.page == .controls { self.dismiss() } else { navigation.page = .controls }
                    return nil
                }
                return event
            }
            if event.window !== self.panel && event.window !== self.item.button?.window &&
                        event.window?.level != .popUpMenu {
                self.dismiss()
            }
            return event
        }
        return true
    }

    private func position(_ panel: NSPanel, size: CGSize) {
        guard let button = item.button, let window = button.window, let screen = window.screen else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen.visibleFrame
        let x = min(max(visible.minX, anchor.midX - size.width / 2), visible.maxX - size.width)
        let top = min(visible.maxY, anchor.minY) - 2
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    @objc private func dismiss() {
        if let outsideClick { NSEvent.removeMonitor(outsideClick) }
        if let localEvent { NSEvent.removeMonitor(localEvent) }
        outsideClick = nil
        localEvent = nil
        panel?.orderOut(nil)
        panel = nil
        item.button?.highlight(false)
    }
}

private final class StatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
