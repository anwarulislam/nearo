# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Users

People who own an Android phone and use a Mac day to day, and want the two to work together the way an iPhone and a Mac do: phone notifications, texts, files and the clipboard on the Mac without picking up the phone. Most of the time Nearo runs in the background; people glance at the menu bar, act on a notification or drop a file, and get back to work. They are not expected to know KDE Connect, networking or certificates.

## Product Purpose

Nearo is a native macOS companion for Android phones, built on the KDE Connect protocol. It mirrors notifications (with inline replies), syncs SMS conversations, shares files and the clipboard both ways, controls phone media and volume, rings the phone, lets the phone act as a trackpad and presentation remote, and runs Mac shell commands the user has set up, triggered from the phone. Success is the phone feeling like part of the Mac: connected without thought, quick to act on, and invisible when idle.

## Positioning

Nearo brings Android messages, phone storage and remote input into native macOS windows, widgets and system controls. Size and idle resource figures come from local measurements of each release candidate. [Current benchmark](docs/performance.md)

## Operating Context

- Lives in the menu bar (LSUIElement agent app, no Dock icon). The menu bar popover is the primary surface; the main window is secondary, for messages, notifications, files, commands and device detail; Settings handles identity, per-device sync and permissions.
- Phone and Mac must share a local network (or a reachable subnet/VPN such as Tailscale). Discovery is UDP broadcast on port 1716, with connect-by-IP as a fallback.
- First use: install KDE Connect on the phone (Google Play or F-Droid), open it on the same Wi-Fi, request pairing, confirm on the Mac.
- The local release script produces separate ad-hoc signed DMGs for Apple Silicon and Intel; first launch goes through Gatekeeper's "Open Anyway".
- Relies on macOS permissions: Notifications (mirroring and replies) and Accessibility (remote input and presenter).

## Capabilities and Constraints

- Target is **macOS** (macOS 15 Sequoia or newer, universal for Apple Silicon and Intel), not iOS. `ios` is recorded above only so Apple-native guidance loads; apply the macOS Human Interface Guidelines and native AppKit/SwiftUI conventions, not iPhone patterns.
- Must stay compatible with the stock KDE Connect Android app (protocol v8). No custom phone app; features are bounded by what that protocol and app support.
- Pure Swift and SwiftUI on Apple frameworks; no third-party dependencies or runtimes. Keep the app small and idle-cheap.
- Local-only: peer-to-peer TLS on the local network, devices pinned by certificate fingerprint. No cloud, accounts, relays or telemetry.
- Terminology: devices are "paired" (trusted) or "nearby" (discovered, unpaired); "Find Phone" rings the phone; "Commands" are user-defined Mac shell commands the phone can trigger.
- Undecided: code signing and notarization; any platform beyond macOS.

## Main window design

The device sidebar and its seven sections follow the Nearo HTML draft. Settings opens in the main window, and Device Settings opens its Devices tab. New sections should use the adaptive colors, original outline icons and shared controls in `Nearo/Views/Components/WorkspaceDesign.swift`. Use grouped surfaces for content and native Liquid Glass for floating actions, with the material fallback on macOS 15.

## Brand Commitments

- Name: Nearo.
- The macOS and Android apps share the Quiet Pulse icon. A small mint dot nestles in the curved edge of a cobalt disc on a midnight-blue tile. The macOS artwork lives in `Nearo/Assets.xcassets/AppIcon.appiconset`.
- License: GPL-2.0, matching the KDE Connect ecosystem.

## Evidence on Hand

- [Release measurements](docs/performance.md) document the build, architecture, environment and units.
- [Feature inventory](docs/features.md) maps the interface to current screenshots and installation requirements.
- No user testimonials, download counts, reviews or press exist. Do not invent them.

## Product Principles

1. **Invisible until needed.** The menu bar is home; the app should cost nothing when idle and ask for attention only when the phone has something worth it.
2. **Native, not ported.** Behave like a first-party Mac app: system controls, materials, shortcuts, permissions and accessibility, never emulated chrome.
3. **Small is a feature.** Every addition is weighed against download size, memory and idle cost.
4. **Private by construction.** Data stays on the local network between devices the user explicitly paired.
5. **Works with what people already have.** The stock KDE Connect Android app is the contract; never require anything extra on the phone.
