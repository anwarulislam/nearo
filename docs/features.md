# Nearo feature inventory

Feature inventory for Nearo 1.0.0. The entries below map shipping features to real interface captures with demonstration data. A settings or control screenshot documents the interface; device-dependent behavior still requires a compatible paired peer and the permissions named below.

[Browse the visual gallery](https://anwar.bd/nearo/gallery) · [Build measurements](performance.md) · [Demo data and source files](demo-data.md) · [Capture guide](captures.md)

## Connection & devices

| Feature | Behavior and requirements | Capture |
| --- | --- | --- |
| First launch | Start discovery or connect by address. | [View](https://anwar.bd/nearo/screenshots/onboarding.jpg) |
| Nearby device | Select a discovered phone and request pairing. | [View](https://anwar.bd/nearo/screenshots/nearby.jpg) |
| Pairing verification | Compare the displayed code on both devices before accepting. | [View](https://anwar.bd/nearo/screenshots/pairing.jpg) |
| Connect by address | Enter a reachable Wi-Fi address or Tailscale name when discovery is unavailable. | [View](https://anwar.bd/nearo/screenshots/connect-by-ip.jpg) |
| Device overview | Check the network, battery and recent activity for the selected device. | [View](https://anwar.bd/nearo/screenshots/overview.jpg) |
| Switch device | Select which paired device the menu controls. | [View](https://anwar.bd/nearo/screenshots/device-picker.jpg) |
| Offline device | See connection status and instructions for reconnecting. | [View](https://anwar.bd/nearo/screenshots/offline.jpg) |

## Messages, calls & notifications

| Feature | Behavior and requirements | Capture |
| --- | --- | --- |
| Messages | Read SMS threads, load earlier messages, and reply from the Mac. | [View](https://anwar.bd/nearo/screenshots/messages.jpg) |
| New message | Choose a contact or enter a number. Supported dual-SIM devices offer a sending SIM. | [View](https://anwar.bd/nearo/screenshots/compose.jpg) |
| Contact book | Find a person, copy their number or start a message. Synced contacts remain available offline. | [View](https://anwar.bd/nearo/screenshots/contacts.jpg) |
| Notifications | Review phone alerts, dismiss them, reply where supported, and copy verification codes. | [View](https://anwar.bd/nearo/screenshots/notifications.jpg) |
| Call history | Review incoming, outgoing and missed calls. Earlier phone history needs Bluetooth phonebook sharing. | [View](https://anwar.bd/nearo/screenshots/calls.jpg) |
| Incoming call | See the caller and silence the phone. Optional call handling pauses Mac media and resumes it afterwards. | [View](https://anwar.bd/nearo/screenshots/call-incoming.jpg) |
| Active call | Keep the elapsed call time visible in a compact floating pill. | [View](https://anwar.bd/nearo/screenshots/call-active.jpg) |
| Reply to an alert | Write an inline response to Mira’s Signal message from the Notifications pane. | [View](https://anwar.bd/nearo/screenshots/notification-reply.jpg) |

## Files, photos & clipboard

| Feature | Behavior and requirements | Capture |
| --- | --- | --- |
| Files workspace | Drop files on Nearo, watch transfer progress, or open the receive folder. | [View](https://anwar.bd/nearo/screenshots/files.jpg) |
| Phone drive in Finder | Browse mounted phone storage and read files on demand. | [View](https://anwar.bd/nearo/screenshots/finder-drive.png) |
| Share from a Mac app | Use Share → Nearo and choose the receiving device. | [View](https://anwar.bd/nearo/screenshots/share-extension.png) |
| Per-device preferences | Choose a download folder and set clipboard and notification preferences for each paired device. | [View](https://anwar.bd/nearo/screenshots/settings-devices.jpg) |
| Finder drive settings | Mount phones over SFTP or configure the optional ADB transport for a device. | [View](https://anwar.bd/nearo/screenshots/settings-files.jpg) |
| Photo library | Browse indexed pictures from the phone drive, filter by folder and save selected photos. | [View](https://anwar.bd/nearo/screenshots/photos.jpg) |
| Photo preview | Open a larger view and save a copy on the Mac. | [View](https://anwar.bd/nearo/screenshots/photo-preview.jpg) |
| Share clipboard text | Send text to the phone. Android’s clipboard-sharing action brings copied text back to the Mac. | [View](https://anwar.bd/nearo/screenshots/clipboard.jpg) |
| Select photos | Select pictures from the architecture walk to save them together. | [View](https://anwar.bd/nearo/screenshots/photo-selection.jpg) |

## Remote input, media & commands

| Feature | Behavior and requirements | Capture |
| --- | --- | --- |
| Remote Input | Lock the Mac pointer to the paired phone, click, scroll, or enter text. | [View](https://anwar.bd/nearo/screenshots/remote-input.jpg) |
| Pointer capture | Option-X releases the cursor. Clicking the left and right mouse buttons together also unlocks it. | [View](https://anwar.bd/nearo/screenshots/remote-input-locked.jpg) |
| Playback controls | View album art, control the phone player and adjust available volume and playback position. | [View](https://anwar.bd/nearo/screenshots/media.jpg) |
| Commands & Shortcuts | Choose the Mac commands that a paired phone can run. Sharing Mac Shortcuts is optional. | [View](https://anwar.bd/nearo/screenshots/commands.jpg) |
| Find the Mac | Ring the Mac from the phone and dismiss the alert when it is found. | [View](https://anwar.bd/nearo/screenshots/ring-mac.jpg) |
| Permissions & presenter | Enable macOS Accessibility for phone-to-Mac input and preview the presenter pointer. | [View](https://anwar.bd/nearo/screenshots/settings-permissions.jpg) |

## Around macOS

| Feature | Behavior and requirements | Capture |
| --- | --- | --- |
| Menu bar | Reach device status, media, the clipboard and file actions while the main window is closed. | [View](https://anwar.bd/nearo/screenshots/menu-bar.jpg) |
| Small widget | Show connection and battery for a pinned phone or follow the selected device. | [View](https://anwar.bd/nearo/screenshots/widget-small.png) |
| Medium widget | Add the current track and artist to device status. | [View](https://anwar.bd/nearo/screenshots/widget-medium.png) |
| Control Center | On macOS 26, add Ring Phone, Send Clipboard, Send Files, Play or Pause, Switch Device and Now Playing on Phone. | [View](https://anwar.bd/nearo/screenshots/control-center.png) |
| General settings | Configure login, Reduce Motion, automatic code copying, call handling, Away Lock and connection options. | [View](https://anwar.bd/nearo/screenshots/settings-general.jpg) |
| Themes & appearance | Choose a workspace palette and follow system appearance, or select Light or Dark. | [View](https://anwar.bd/nearo/screenshots/settings-themes.jpg) |
| Dark appearance | Read device status and notifications in a dark workspace. | [View](https://anwar.bd/nearo/screenshots/overview-dark.jpg) |
| Software updates | Review release information and configure automatic checks. Installation depends on build signing. | [View](https://anwar.bd/nearo/screenshots/updater.jpg) |

## Browser workspace

| Feature | Behavior and requirements | Capture |
| --- | --- | --- |
| Overview in the browser | Use the private browser workspace served by Nearo on this Mac. | [View](https://anwar.bd/nearo/screenshots/web-overview.jpg) |
| Browser messages | Read conversations and send text from the browser. | [View](https://anwar.bd/nearo/screenshots/web-messages.jpg) |
| Browser calls | Browse call entries and request earlier history. | [View](https://anwar.bd/nearo/screenshots/web-calls.jpg) |
| Browser contacts | Search synced contacts and find a number. | [View](https://anwar.bd/nearo/screenshots/web-contacts.jpg) |
| Browser notifications | Read and act on supported notifications. | [View](https://anwar.bd/nearo/screenshots/web-notifications.jpg) |
| Browser photos | Browse phone photos and save selected pictures. | [View](https://anwar.bd/nearo/screenshots/web-photos.jpg) |
| Browser files | Monitor transfers and use the Mac file picker to send files. | [View](https://anwar.bd/nearo/screenshots/web-files.jpg) |
| Browser commands | Run a configured command from the local workspace. | [View](https://anwar.bd/nearo/screenshots/web-commands.jpg) |

## Behaviors behind the screens

| Feature | How it works | Related interface |
| --- | --- | --- |
| Automatic discovery and reconnect | Wi-Fi discovery uses UDP and Bonjour. Tailscale discovery is optional. A manually entered address must be reachable. Bluetooth transport is beta. | [Connect by address](https://anwar.bd/nearo/screenshots/connect-by-ip.jpg) |
| Device trust | Pairing pins the peer certificate. Compatible existing KDE Connect Mac identities and pairings can be imported. Unpair from Devices settings. | [Pairing](https://anwar.bd/nearo/screenshots/pairing.jpg) |
| Notification actions | Available replies follow Android’s notification actions. Nearo can suppress duplicate native-app alerts and optionally copy one-time codes automatically. Grant Android notification access and macOS Notifications. | [Notifications](https://anwar.bd/nearo/screenshots/notifications.jpg) |
| File receive location | Each paired device starts at `~/Downloads`. Choose a new folder in Settings → Devices or reset to the default. | [Device settings](https://anwar.bd/nearo/screenshots/settings-devices.jpg) |
| Phone drive and photos | SFTP uses the peer’s file-browsing permission. Optional ADB uses wireless debugging and requires adb on the Mac. Previously indexed photo metadata and contacts can be browsed offline. | [Drive settings](https://anwar.bd/nearo/screenshots/settings-files.jpg) |
| Share links and text | The Share extension accepts files, URLs and text. Shared links can open on the receiving device. Clipboard sync is configurable per device. | [Share extension](https://anwar.bd/nearo/screenshots/share-extension.png) |
| Calls and media | Choose whether to display the floating call card and pause/resume supported Mac players. Call audio stays on the phone. | [Call history](https://anwar.bd/nearo/screenshots/calls.jpg) |
| Media in either direction | Phone media controls require an active supported player. The Android multimedia controller can control supported Mac players and Mac volume. | [Playback](https://anwar.bd/nearo/screenshots/media.jpg) |
| Find either device | Ring the phone from Overview or Control Center. The companion can ring the Mac. | [Overview](https://anwar.bd/nearo/screenshots/overview.jpg) |
| Remote Input in either direction | Mac-to-phone pointer and keyboard require the phone receiver and its permissions. Phone-to-Mac input and presentation control require macOS Accessibility. | [Mac-to-phone input](https://anwar.bd/nearo/screenshots/remote-input.jpg) · [Mac permissions](https://anwar.bd/nearo/screenshots/settings-permissions.jpg) |
| Away Lock | An opt-in setting locks the Mac after the paired phone has been disconnected for about half a minute. | [General settings](https://anwar.bd/nearo/screenshots/settings-general.jpg) |
| Browser access | Enable in General. Open the private link on the same Mac. An optional Apache setup supports a portless local address. Disable the server or quit to end the session. | [Browser workspace](https://anwar.bd/nearo/screenshots/web-overview.jpg) |
| Updates | The updater checks release metadata and verifies compatible signed archives. Ad-hoc builds use the download-page path. | [Updater](https://anwar.bd/nearo/screenshots/updater.jpg) |

## Phone-side captures

Placeholder by request. Add shareable Android screenshots for pairing, focused text and scrolling, a notification reply, a file arriving, multimedia controls, clipboard sharing, commands and presentation input when the test phone is available. A screenshot of the Mac controls does not verify an end-to-end phone action.
