import AppKit
import Carbon.HIToolbox

/// Captures events only while the Remote Input window is key.
@MainActor
@Observable
final class RemotePointerCapture {
    private(set) var isLocked = false
    private(set) var error: String?
    private var monitor: Any?
    private weak var window: NSWindow?
    private var previouslyAcceptedMouseMoves = false
    private var dragging = false
    private var send: (([String: Any]) -> Void)?

    private var phoneScroll: PhoneScroll?

    func start(isPhone: Bool, send: @escaping ([String: Any]) -> Void) {
        guard !isLocked, let window = NSApp.keyWindow else { return }
        error = nil
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged,
            .otherMouseDragged, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .scrollWheel, .keyDown]
        guard let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }) else {
            error = "Couldn’t start pointer capture."
            return
        }
        guard CGAssociateMouseAndMouseCursorPosition(0) == .success else {
            NSEvent.removeMonitor(monitor)
            error = "Couldn’t lock the Mac pointer."
            return
        }
        phoneScroll = isPhone ? PhoneScroll() : nil
        self.monitor = monitor
        previouslyAcceptedMouseMoves = window.acceptsMouseMovedEvents
        window.acceptsMouseMovedEvents = true
        self.window = window
        self.send = send
        NSCursor.hide()
        isLocked = true
    }

    func stop(ifWindow closingWindow: NSWindow?) {
        if closingWindow === window { stop() }
    }

    func stop() {
        guard isLocked else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        CGAssociateMouseAndMouseCursorPosition(1)
        window?.acceptsMouseMovedEvents = previouslyAcceptedMouseMoves
        NSCursor.unhide()
        isLocked = false
        if dragging { send?(["singlerelease": true]) }
        send?([:]) // KDE Connect hides the remote pointer on an empty mouse request.
        dragging = false
        send = nil
        window = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard window?.isKeyWindow == true else {
            stop()
            return event
        }
        switch event.type {
        case .keyDown:
            guard event.keyCode == kVK_ANSI_X, event.modifierFlags.contains(.option) else { return event }
            stop()
        case .leftMouseDown, .rightMouseDown:
            if NSEvent.pressedMouseButtons & 3 == 3 { stop() }
        case .leftMouseUp:
            send?(dragging ? ["singlerelease": true] : ["singleclick": true])
            dragging = false
        case .rightMouseUp: send?(["rightclick": true])
        case .otherMouseUp:
            if event.buttonNumber == 2 { send?(["middleclick": true]) }
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            if event.type == .leftMouseDragged, !dragging {
                dragging = true
                send?(["singlehold": true])
            }
            if event.deltaX != 0 || event.deltaY != 0 {
                send?(["dx": Double(event.deltaX), "dy": Double(event.deltaY)])
            }
        case .scrollWheel:
            if phoneScroll != nil {
                guard event.momentumPhase.isEmpty else { return nil }
                if event.phase.contains(.began) { phoneScroll = PhoneScroll() }
                if let dy = phoneScroll?.step(delta: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas) {
                    send?(["scroll": true, "dx": 0, "dy": dy])
                }
            } else {
                send?(["scroll": true, "dx": Double(event.scrollingDeltaX), "dy": Double(event.scrollingDeltaY)])
            }
        default: break
        }
        return nil
    }
}

// Android's accessibility receiver performs one scroll action at ±500 and drops
// the excess. Accumulate trackpad points locally so a swipe sends discrete steps.
struct PhoneScroll {
    private var distance: CGFloat = 0

    mutating func step(delta: CGFloat, precise: Bool) -> Int? {
        guard delta != 0 else { return nil }
        if distance * delta < 0 { distance = 0 }
        distance += delta
        if precise && abs(distance) < 32 { return nil }
        distance = precise ? distance.truncatingRemainder(dividingBy: 32) : 0
        return delta < 0 ? 500 : -500
    }
}
