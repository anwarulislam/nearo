//
//  InputSynthesizer.swift
//  Nearo
//
//  Synthesizes mouse and keyboard events using CoreGraphics.
//  Direct port of upstream macOS remote input (macosremoteinput.mm).
//

import Foundation
import CoreGraphics
import ApplicationServices
import Carbon.HIToolbox
import AppKit

public final class InputSynthesizer: @unchecked Sendable {
    public static let shared = InputSynthesizer()

    private let lock = NSLock()
    private var isLeftButtonPressed = false

    /// Upstream SpecialKeysMap table verbatim (macosremoteinput.mm:16-50)
    private static let specialKeysMap: [CGKeyCode] = [
        0,                                      // 0: Invalid
        CGKeyCode(kVK_Delete),                  // 1
        CGKeyCode(kVK_Tab),                     // 2
        CGKeyCode(kVK_Return),                  // 3
        CGKeyCode(kVK_LeftArrow),               // 4
        CGKeyCode(kVK_UpArrow),                 // 5
        CGKeyCode(kVK_RightArrow),              // 6
        CGKeyCode(kVK_DownArrow),               // 7
        CGKeyCode(kVK_PageUp),                  // 8
        CGKeyCode(kVK_PageDown),                // 9
        CGKeyCode(kVK_Home),                    // 10
        CGKeyCode(kVK_End),                     // 11
        CGKeyCode(kVK_Return),                  // 12
        CGKeyCode(kVK_ForwardDelete),           // 13
        CGKeyCode(kVK_Escape),                  // 14
        0,                                      // 15
        0,                                      // 16
        CGKeyCode(kVK_Control),                 // 17
        CGKeyCode(kVK_Option),                  // 18
        CGKeyCode(kVK_Shift),                   // 19
        CGKeyCode(kVK_Command),                 // 20
        CGKeyCode(kVK_F1),                      // 21
        CGKeyCode(kVK_F2),                      // 22
        CGKeyCode(kVK_F3),                      // 23
        CGKeyCode(kVK_F4),                      // 24
        CGKeyCode(kVK_F5),                      // 25
        CGKeyCode(kVK_F6),                      // 26
        CGKeyCode(kVK_F7),                      // 27
        CGKeyCode(kVK_F8),                      // 28
        CGKeyCode(kVK_F9),                      // 29
        CGKeyCode(kVK_F10),                     // 30
        CGKeyCode(kVK_F11),                     // 31
        CGKeyCode(kVK_F12),                     // 32
    ]

    private init() {}

    /// Checks if accessibility permission is granted to synthesize events.
    public var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user to grant accessibility permission in System Settings.
    public func promptAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Opens System Settings -> Privacy & Security -> Accessibility
    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Handles a kdeconnect.mousepad.request packet and synthesizes events.
    @discardableResult
    public func handlePacket(_ packet: NetworkPacket) -> Bool {
        guard isAccessibilityTrusted else {
            NearoLog("[InputSynthesizer] Dropped event: Accessibility permission not granted")
            return false
        }

        let dx = packet.double(for: "dx")
        let dy = packet.double(for: "dy")
        let x = packet.has("x") ? packet.double(for: "x") : nil
        let y = packet.has("y") ? packet.double(for: "y") : nil

        let isSingleClick = packet.bool(for: "singleclick")
        let isDoubleClick = packet.bool(for: "doubleclick")
        let isMiddleClick = packet.bool(for: "middleclick")
        let isRightClick = packet.bool(for: "rightclick")
        let isSingleHold = packet.bool(for: "singlehold")
        let isSingleRelease = packet.bool(for: "singlerelease")
        let isScroll = packet.bool(for: "scroll")
        let key = packet.string(for: "key") ?? ""
        let specialKey = packet.int(for: "specialKey")
        let validSpecialKey = (specialKey > 0 && specialKey < Self.specialKeysMap.count)

        if isSingleClick || isDoubleClick || isMiddleClick || isRightClick ||
            isSingleHold || isSingleRelease || isScroll || !key.isEmpty || validSpecialKey {

            let currentPoint = currentMousePosition()

            if isSingleClick {
                postMouseEvent(type: .leftMouseDown, point: currentPoint, button: .left)
                postMouseEvent(type: .leftMouseUp, point: currentPoint, button: .left)
                lock.withLock { self.isLeftButtonPressed = false }
            } else if isDoubleClick {
                // First click
                postMouseEvent(type: .leftMouseDown, point: currentPoint, button: .left)
                postMouseEvent(type: .leftMouseUp, point: currentPoint, button: .left)

                // Second click with click state = 2
                if let eventDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: currentPoint, mouseButton: .left) {
                    eventDown.setIntegerValueField(.mouseEventClickState, value: 2)
                    eventDown.post(tap: .cghidEventTap)
                }
                if let eventUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: currentPoint, mouseButton: .left) {
                    eventUp.setIntegerValueField(.mouseEventClickState, value: 2)
                    eventUp.post(tap: .cghidEventTap)
                }
                lock.withLock { self.isLeftButtonPressed = false }
            } else if isMiddleClick {
                postMouseEvent(type: .otherMouseDown, point: currentPoint, button: .center)
                postMouseEvent(type: .otherMouseUp, point: currentPoint, button: .center)
            } else if isRightClick {
                postMouseEvent(type: .rightMouseDown, point: currentPoint, button: .right)
                postMouseEvent(type: .rightMouseUp, point: currentPoint, button: .right)
            } else if isSingleHold {
                postMouseEvent(type: .leftMouseDown, point: currentPoint, button: .left)
                lock.withLock { self.isLeftButtonPressed = true }
            } else if isSingleRelease {
                postMouseEvent(type: .leftMouseUp, point: currentPoint, button: .left)
                lock.withLock { self.isLeftButtonPressed = false }
            } else if isScroll {
                // dy = vertical, -dx = horizontal scroll
                if let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(dy), wheel2: -Int32(dx), wheel3: 0) {
                    event.post(tap: .cghidEventTap)
                }
            } else if !key.isEmpty || validSpecialKey {
                let ctrl = packet.bool(for: "ctrl")
                let alt = packet.bool(for: "alt")
                let shift = packet.bool(for: "shift")
                let superKey = packet.bool(for: "super")

                var flags: CGEventFlags = []
                if ctrl { flags.insert(.maskControl) }
                if alt { flags.insert(.maskAlternate) }
                if shift { flags.insert(.maskShift) }
                if superKey { flags.insert(.maskCommand) }

                // Press modifiers
                if ctrl { postKeyEvent(keyCode: CGKeyCode(kVK_Control), isDown: true) }
                if alt { postKeyEvent(keyCode: CGKeyCode(kVK_Option), isDown: true) }
                if shift { postKeyEvent(keyCode: CGKeyCode(kVK_Shift), isDown: true) }
                if superKey { postKeyEvent(keyCode: CGKeyCode(kVK_Command), isDown: true) }

                if validSpecialKey {
                    let code = Self.specialKeysMap[specialKey]
                    // Mission Control inspects the flags on the arrow itself. Posting
                    // Control immediately beforehand does not reliably set those flags.
                    postKeyEvent(keyCode: code, isDown: true, modifiers: flags)
                    postKeyEvent(keyCode: code, isDown: false, modifiers: flags)
                } else if !flags.isEmpty, key.count == 1 {
                    if let stroke = Self.shortcutKey(for: key) {
                        let modifiers = flags.union(stroke.shift ? .maskShift : [])
                        postKeyEvent(keyCode: stroke.code, isDown: true, modifiers: modifiers)
                        postKeyEvent(keyCode: stroke.code, isDown: false, modifiers: modifiers)
                    }
                } else {
                    for char in key.utf16 {
                        var unichar = char
                        if let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) {
                            event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)
                            event.post(tap: .cgSessionEventTap)
                        }
                    }
                }

                // Release modifiers in reverse order
                if superKey { postKeyEvent(keyCode: CGKeyCode(kVK_Command), isDown: false) }
                if shift { postKeyEvent(keyCode: CGKeyCode(kVK_Shift), isDown: false) }
                if alt { postKeyEvent(keyCode: CGKeyCode(kVK_Option), isDown: false) }
                if ctrl { postKeyEvent(keyCode: CGKeyCode(kVK_Control), isDown: false) }
            }
        } else {
            // Mouse move / drag event
            if dx != 0 || dy != 0 {
                let current = currentMousePosition()
                let target = CGPoint(x: current.x + CGFloat(dx), y: current.y + CGFloat(dy))
                setMousePosition(target)
            } else if let x = x, let y = y {
                setMousePosition(CGPoint(x: CGFloat(x), y: CGFloat(y)))
            }
        }

        return true
    }

    // MARK: - Event Helpers

    private func currentMousePosition() -> CGPoint {
        // CGEvent(source: nil)?.location gives global screen coordinates where (0,0) is top-left
        if let event = CGEvent(source: nil) {
            return event.location
        }
        return .zero
    }

    private func setMousePosition(_ point: CGPoint) {
        let isDragging = lock.withLock { self.isLeftButtonPressed }
        if isDragging {
            // When button is held, posting leftMouseDragged is mandatory for OS selection and window dragging
            postMouseEvent(type: .leftMouseDragged, point: point, button: .left)
        } else {
            CGWarpMouseCursorPosition(point)
        }
    }

    private func postMouseEvent(type: CGEventType, point: CGPoint, button: CGMouseButton) {
        if let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button) {
            event.post(tap: .cghidEventTap)
        }
    }

    private func postKeyEvent(keyCode: CGKeyCode, isDown: Bool, modifiers: CGEventFlags = []) {
        if let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: isDown) {
            event.flags.formUnion(modifiers)
            event.post(tap: .cghidEventTap)
        }
    }

    /// Resolve shortcut characters against the Mac's keyboard layout. A Unicode
    /// text event with virtual key 0 looks like the A key to shortcut handlers.
    private static func shortcutKey(for character: String) -> (code: CGKeyCode, shift: Bool)? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        let target = character.lowercased()
        let keyboardType = UInt32(LMGetKbdType())
        return withExtendedLifetime(source) {
            for shifted in [false, true] {
                for code: UInt16 in 0..<128 {
                    var deadKey: UInt32 = 0
                    var length = 0
                    var chars = [UniChar](repeating: 0, count: 4)
                    let result = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay),
                                                shifted ? UInt32(shiftKey >> 8) : 0, keyboardType,
                                                OptionBits(kUCKeyTranslateNoDeadKeysMask),
                                                &deadKey, chars.count, &length, &chars)
                    if result == noErr, length > 0, String(utf16CodeUnits: chars, count: length) == target {
                        return (code, shifted)
                    }
                }
            }
            return nil
        }
    }

    // MARK: - Media keys

    enum MediaKey: Int32 {
        case playPause = 16 // NX_KEYTYPE_PLAY
        case next = 17      // NX_KEYTYPE_NEXT
        case previous = 18  // NX_KEYTYPE_PREVIOUS
    }

    /// Presses a media key, as the keyboard's ⏯ ⏭ ⏮ do. Unlike MediaRemote
    /// commands, every player obeys these, Safari included. Returns false
    /// without Accessibility access.
    @discardableResult
    func pressMediaKey(_ key: MediaKey) -> Bool {
        guard isAccessibilityTrusted else { return false }
        for down in [true, false] {
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00),
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: 8, data1: Int((key.rawValue << 16) | ((down ? 0xa : 0xb) << 8)), data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
        return true
    }
}
