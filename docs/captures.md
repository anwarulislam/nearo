# Reproduce the gallery captures

The gallery uses the Pixel 10 and Samsung Galaxy Tab S10+ demo pairing, with contact, message, call and photo examples from an architecture photo walk. The browser and Mac windows share the same demo model. Use a demo build or a separate test pairing when taking screenshots.

## Mac windows and menus

From the repository root, run `scripts/capture-native.sh`. The script runs the opt-in native snapshot and interaction tests, keeps their Retina originals and test attachments in a new directory under `.build/captures/`, and exports verified JPEGs to `.build/captures/screenshots/`. It drives the Mac UI while capturing menus, pointer lock, text entry and photo selection, so run it when the desktop is available.

## Browser workspace

From the repository root, run the opt-in WebKit capture. It starts Nearo’s actual web server on a loopback port with an isolated browser session, visits eight device sections, and writes an uncompressed PNG for each to the selected directory.

```sh
mkdir -p .build/gallery-masters .build/captures/screenshots
TEST_RUNNER_NEARO_MARKETING_DIR="$PWD/.build/gallery-masters" \
  xcodebuild -scheme Nearo -destination 'platform=macOS' -derivedDataPath .build \
  -parallel-testing-enabled NO -only-testing:NearoTests/WebMarketingCaptures \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO test
for file in .build/gallery-masters/web-*.png; do
  sips --resampleWidth 1600 --setProperty format jpeg --setProperty formatOptions 90 \
    "$file" --out ".build/captures/screenshots/$(basename "$file" .png).jpg"
done
```

The published workspace images show the browser content area. A browser address bar or the private session link should stay outside the frame.

## Widgets and Share

Open `NearoWidgets/NearoDeviceWidget.swift` in Xcode and use the small and medium Device Status previews. Both use the extension’s preview timeline entry. The small widget shows the phone and battery. The medium widget also shows the track and artist. The gallery PNGs render that SwiftUI content with dark rounded presentation backgrounds.

The two-device chooser in `NearoShare/ShareViewController.swift` has its own SwiftUI preview. It shows the Share extension after choosing Nearo while two devices are connected. Capture it in dark appearance with the full device names visible.

## Finder and Control Center

The Finder image was taken from a real Finder window browsing Nearo’s loopback NFS server. A read-only sample transport supplied the photo-walk folders. To reproduce with a test phone, give the pairing the demo phone name and populate the test storage with the project folders shown in the shot. Open the mounted volume in a new Finder window, select icon view, hide the toolbar and sidebar, and capture only that window.

For the system controls, open macOS Control Center, choose **Edit Controls**, then select **Nearo** in the gallery. Capture the gallery window with all six controls visible; close editing without adding or removing a control. The controls are device-independent, so this shot has no phone name, messages or other fixture values.

The operating system’s notification banner and physical Android screens require separate captures. The in-app notifications and reply views show Nearo’s own interface.

## Browser and system asset names

| Source | Files under `.build/captures/screenshots/` |
| --- | --- |
| Browser workspace | `web-overview.jpg`, `web-messages.jpg`, `web-photos.jpg`, `web-calls.jpg`, `web-contacts.jpg`, `web-notifications.jpg`, `web-files.jpg`, `web-commands.jpg` |
| Device Status widget | `widget-small.png`, `widget-medium.png` |
| Share extension device chooser | `share-extension.png` |
| Finder phone volume | `finder-drive.png` |
| macOS Control Center gallery | `control-center.png` |

Copy the chosen images into the website project’s `public/nearo/screenshots/` directory. The three screenshots embedded in the app README live in `docs/screenshots/`.
