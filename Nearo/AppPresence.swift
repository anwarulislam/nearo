//
//  AppPresence.swift
//  Nearo
//

import AppKit

/// Flips the app between accessory (menu-bar-only) and regular (Dock icon +
/// app menu) based on whether any app window is open. The MenuBarExtra
/// popover is not an app window and never affects this.
enum AppPresence {
    private static var openWindows = 0

    static func windowDidAppear() {
        openWindows += 1
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
    }

    static func windowDidDisappear() {
        openWindows = max(0, openWindows - 1)
        if openWindows == 0 {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
