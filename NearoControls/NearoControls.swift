import AppIntents
import SwiftUI
import WidgetKit

@main
struct NearoControls: WidgetBundle {
    var body: some Widget {
        SwitchDeviceControl()
        NowPlayingControl()
        RingControl()
        ClipboardControl()
        SendFilesControl()
        PlaybackControl()
    }
}

private protocol DeviceControl: ControlWidget {
    var action: NearoControlAction { get }
    var title: LocalizedStringResource { get }
    var icon: String { get }
}

private extension DeviceControl {

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.anwar.Nearo.controls." + action.rawValue) {
            ControlWidgetButton(action: NativeControlIntent(action)) {
                Label(String(localized: title), systemImage: icon)
            }
        }
        .displayName(title)
        .description("Use this action on the device selected in Nearo.")
    }
}

private struct RingControl: DeviceControl {
    let action = NearoControlAction.ring
    let title: LocalizedStringResource = "Ring Phone"
    let icon = "iphone.radiowaves.left.and.right"
}

private struct ClipboardControl: DeviceControl {
    let action = NearoControlAction.clipboard
    let title: LocalizedStringResource = "Send Clipboard"
    let icon = "doc.on.clipboard"
}

private struct SendFilesControl: DeviceControl {
    let action = NearoControlAction.sendFiles
    let title: LocalizedStringResource = "Send Files"
    let icon = "paperplane"
}

private struct PlaybackControl: DeviceControl {
    let action = NearoControlAction.playback
    let title: LocalizedStringResource = "Play or Pause"
    let icon = "playpause"
}

private struct SwitchDeviceControl: DeviceControl {
    let action = NearoControlAction.switchDevice
    let title: LocalizedStringResource = "Switch Device"
    let icon = "ipad.and.iphone"
}

private struct NowPlayingControl: DeviceControl {
    let action = NearoControlAction.nowPlaying
    let title: LocalizedStringResource = "Now Playing on Phone"
    let icon = "music.note"
}
