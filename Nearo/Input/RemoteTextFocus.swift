import AppKit
import ApplicationServices

/// Watches the identity and role of the focused control, never its contents.
final class RemoteTextFocus {
    private let system = AXUIElementCreateSystemWide()
    private var previous: AXUIElement?
    private(set) var token = ""
    var onChange: ((String) -> Void)?
    private var timer: Timer?
    private var observer: AXObserver?
    private var observedPID: pid_t?
    private var appActivation: NSObjectProtocol?
    private var mouseMonitor: Any?
    private var localMonitor: Any?

    func start() {
        guard timer == nil else { return }
        observeFrontmostApp()
        appActivation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.observeFrontmostApp()
            self?.refresh()
        }
        let clicked: (NSEvent) -> Void = { [weak self] event in
            guard let self, let point = event.cgEvent?.location else { return }
            let clickToken = self.token
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                guard let self, self.timer != nil else { return }
                self.refresh(click: clickToken == self.token ? point : nil)
            }
        }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: clicked)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
            clicked(event)
            return event
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            // Some custom and web controls omit focus-change notifications.
            self?.observeFrontmostApp()
            self?.refresh()
        }
    }

    private func observeFrontmostApp() {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier, pid != observedPID else { return }
        removeFocusObserver()
        observedPID = pid
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        var next: AXObserver?
        let result = AXObserverCreate(pid, { _, _, _, context in
            guard let context else { return }
            Unmanaged<RemoteTextFocus>.fromOpaque(context).takeUnretainedValue().refresh()
        }, &next)
        guard result == .success, let next else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(next, app, kAXFocusedUIElementChangedNotification as CFString, context)
        AXObserverAddNotification(next, app, kAXFocusedWindowChangedNotification as CFString, context)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(next), .commonModes)
        observer = next
    }

    private func removeFocusObserver() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        observedPID = nil
    }

    func stop() {
        removeFocusObserver()
        if let appActivation { NSWorkspace.shared.notificationCenter.removeObserver(appActivation) }
        appActivation = nil
        timer?.invalidate()
        timer = nil
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        mouseMonitor = nil
        localMonitor = nil
    }

    private func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }

    private func elementAttribute(_ element: AXUIElement, _ key: String) -> AXUIElement? {
        guard let value = attribute(element, key), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func editable(_ element: AXUIElement) -> Bool {
        guard let role = attribute(element, kAXRoleAttribute) as? String else { return false }
        if attribute(element, kAXEnabledAttribute) as? Bool == false { return false }
        if let editable = attribute(element, "AXEditable") as? Bool { return editable }
        switch role {
        case kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole:
            return true
        default:
            return false
        }
    }

    func refresh(click: CGPoint? = nil) {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value)
        // An unresponsive app has not necessarily blurred its text field.
        guard status == .success || status == .noValue || status == .attributeUnsupported else { return }
        let focused: AXUIElement?
        if let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
            focused = (value as! AXUIElement)
        } else {
            focused = nil
        }
        let field = focused.flatMap { editable($0) ? $0 : nil }
        let repeatedClick = click.flatMap { point in field.map { hitField($0, point) } } ?? false
        if let field, let previous, CFEqual(field, previous), !repeatedClick { return }
        if field == nil && previous == nil { return }
        previous = field
        token = field == nil ? "" : UUID().uuidString
        onChange?(token)
    }

    private func hitField(_ field: AXUIElement, _ point: CGPoint) -> Bool {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success else { return false }
        for _ in 0..<12 {
            guard let element = hit else { break }
            if CFEqual(element, field) { return true }
            hit = elementAttribute(element, kAXParentAttribute)
        }
        return false
    }
}
