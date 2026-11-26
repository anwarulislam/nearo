import AppIntents
import Foundation

enum NearoControlAction: String, AppEnum {
    case ring, clipboard, sendFiles, playback, switchDevice, nowPlaying

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Nearo action")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .ring: "Ring Phone", .clipboard: "Send Clipboard", .sendFiles: "Send Files", .playback: "Play or Pause",
        .switchDevice: "Switch Device", .nowPlaying: "Now Playing on Phone"
    ]
}

@available(macOS 26.0, *)
struct NativeControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Control Nearo Device"
    static let supportedModes: IntentModes = .foreground(.immediate)
    // The macOS 26 SDK shipped with the CI toolchain has no execution-target API.
    #if compiler(>=6.4)
    @available(macOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @Parameter(title: "Action") var action: NearoControlAction

    init() {}
    init(_ action: NearoControlAction) { self.action = action }

    @MainActor func perform() async throws -> some IntentResult {
        try runAction()
        return .result()
    }

    @MainActor private func runAction() throws {
        #if NEARO_CONTROL_EXTENSION
        throw ControlFailure("Open Nearo to use this control.")
        #else
        func selectedDevice() throws -> DeviceViewModel {
            guard let device = NearoControlSession.model?.primaryDevice else {
                throw ControlFailure("Connect a paired device in Nearo first.")
            }
            return device
        }
        switch action {
        case .switchDevice, .nowPlaying:
            if action == .nowPlaying { _ = try selectedDevice() }
            guard NearoControlSession.showPanel?(action == .switchDevice ? .devices : .media) == true else {
                throw ControlFailure("Nearo’s menu is unavailable. Open Nearo and try again.")
            }
        case .ring: try selectedDevice().findMyPhone()
        case .clipboard:
            let device = try selectedDevice()
            guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty,
                  device.shareClipboardText(text) else {
                throw ControlFailure("Copy some text and enable clipboard sharing for this device.")
            }
        case .sendFiles:
            let device = try selectedDevice()
            let files = FilePicker.chooseFiles(sendingTo: device.name)
            if !files.isEmpty { device.sendFiles(files) }
        case .playback:
            let device = try selectedDevice()
            guard device.hasNowPlaying else { throw ControlFailure("Start playing media on the selected device first.") }
            device.playPauseMedia()
        }
        #endif
    }
}

private struct ControlFailure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

#if !NEARO_CONTROL_EXTENSION
import AppKit

@MainActor enum NearoControlSession {
    static var showPanel: ((MenuNavigation.Page) -> Bool)?
    static weak var model: NearoAppModel?
}
#endif
