#!/bin/zsh
# Capture Nearo's macOS screens using the app's demonstration devices.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/captures .build/captures/screenshots
run_dir=$(mktemp -d "$PWD/.build/captures/run-XXXXXX")
export TEST_RUNNER_NEARO_SNAPSHOT_DIR="$run_dir/masters"
mkdir -p "$TEST_RUNNER_NEARO_SNAPSHOT_DIR"

xcodebuild test -project Nearo.xcodeproj -scheme Nearo -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build \
  -resultBundlePath "$run_dir/results.xcresult" -parallel-testing-enabled NO \
  -only-testing:NearoTests/UISnapshots \
  -only-testing:NearoUITests/NearoUITests/testRemoteInputWindowLocksSendsTextAndReleases \
  -only-testing:NearoUITests/NearoUITests/testMarketingInteractions \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO

xcrun xcresulttool export attachments --path "$run_dir/results.xcresult" --output-path "$run_dir/attachments"
python3 - "$run_dir" <<'PY'
import json
from pathlib import Path
import struct
import subprocess
import sys

run = Path(sys.argv[1])
masters = run / "masters"
assets = {
    "call-active": "call-active", "call-incoming": "call-incoming", "clipboard": "clipboard",
    "connect-by-ip": "connect-ip-light", "compose": "live-compose", "device-picker": "menu-devices",
    "media": "menu-media", "menu-bar": "menubar-dark", "nearby": "main-nearby-light",
    "notification-reply": "notification-reply", "offline": "main-offline-dark",
    "onboarding": "main-onboarding-light", "overview-dark": "live-overview-dark",
    "pairing": "pair-request-light", "photo-preview": "photo-preview", "photo-selection": "photo-selection",
    "ring-mac": "ringing-dark", "settings-devices": "live-settings-devices",
    "settings-files": "files-settings-light", "settings-general": "settings-light",
    "settings-permissions": "settings-permissions-light", "settings-themes": "settings-themes-dark",
    "updater": "update-uptodate",
}
for section in ("overview", "messages", "calls", "photos", "contacts", "notifications", "files", "commands"):
    assets[section] = "live-" + section
sources = {name: masters / (stem + ".png") for name, stem in assets.items()}
attachments = run / "attachments"
for test in json.loads((attachments / "manifest.json").read_text()):
    for item in test.get("attachments", []):
        title = item["suggestedHumanReadableName"]
        for prefix, output in (("Themed Remote Input window", "remote-input"), ("Remote Input locked", "remote-input-locked")):
            if title.startswith(prefix):
                sources[output] = attachments / item["exportedFileName"]
assert {"remote-input", "remote-input-locked"} <= sources.keys()
for src in sources.values():
    if not src.is_file():
        raise FileNotFoundError(src)
for name, src in sources.items():
    target = Path(".build/captures/screenshots") / (name + ".jpg")
    # Keep the Retina originals in .build and publish smaller JPEG derivatives.
    with src.open("rb") as stream:
        stream.seek(16)  # Width and height in the PNG header.
        width, height = struct.unpack(">II", stream.read(8))
    resize = ["-Z", "1800"] if max(width, height) > 1800 else []
    subprocess.run(["sips", *resize, "-s", "format", "jpeg", "-s", "formatOptions", "90",
                    str(src), "--out", str(target)], stdout=subprocess.DEVNULL, check=True)
print(f"Wrote {len(sources)} native screenshots; originals in {run}.")
PY
