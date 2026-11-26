#!/bin/zsh
# Exercise a 1.0.0 -> 1.0.1 install with a temporary signer and local feed.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
keychain="$work/test.keychain-db"
cleanup() {
  if [[ -n ${server_pid:-} ]]; then kill "$server_pid" 2>/dev/null || true; fi
  security delete-keychain "$keychain" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

# The test key never becomes a release identity. Scope codesign to this keychain.
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj '/CN=Nearo Updater Test' \
  -addext 'basicConstraints=critical,CA:false' -addext 'keyUsage=critical,digitalSignature' -addext 'extendedKeyUsage=critical,codeSigning' \
  -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
  -out "$work/test.p12" -passout pass:test
security create-keychain -p test "$keychain"
security unlock-keychain -p test "$keychain"
security import "$work/test.p12" -k "$keychain" -P test -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k test "$keychain" >/dev/null

# On GitHub's disposable macOS runner, explicitly trust the self-signed fixture
# for code signing before asking codesign to resolve it.
if [[ ${GITHUB_ACTIONS:-} == true ]]; then
  security set-keychain-settings -lut 21600 "$keychain"
  security list-keychains -d user -s "$keychain" "$HOME/Library/Keychains/login.keychain-db"
  sudo security add-trusted-cert -d -r trustRoot -p codeSign -k /Library/Keychains/System.keychain "$work/cert.pem"
fi
identity=$(openssl x509 -in "$work/cert.pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d :)
security find-identity -p codesigning "$keychain" | grep -F "$identity" >/dev/null

if [[ ${GITHUB_ACTIONS:-} == true ]]; then
  security list-keychains -d user
  security find-identity -v -p codesigning "$keychain"
  cp /usr/bin/true "$work/signing-check"
  /usr/bin/codesign --force --sign "$identity" "$work/signing-check"
fi

# Sign the real built app and its embedded extensions, using disposable copies.
xcode=(xcodebuild -project Nearo.xcodeproj -scheme Nearo -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build)
"${xcode[@]}" build -quiet
fixture="$work/fixture"
mkdir -p "$fixture" "$work/new"
ditto .build/Build/Products/Debug/Nearo.app "$fixture/old.app"
ditto "$fixture/old.app" "$work/new/Nearo.app"
for entry in "old 1.0.0" "new 1.0.1"; do
  name=${entry%% *}
  app="$work/new/Nearo.app"
  if [[ "$name" == old ]]; then app="$fixture/old.app"; fi
  plutil -replace CFBundleShortVersionString -string "${entry##* }" "$app/Contents/Info.plist"
  codesign --force --deep --keychain "$keychain" --sign "$identity" "$app"
  codesign --verify --strict --deep "$app"
done
ditto -c -k --keepParent "$work/new/Nearo.app" "$fixture/new.zip"
codesign --force --deep --sign - "$work/new/Nearo.app"
ditto -c -k --keepParent "$work/new/Nearo.app" "$fixture/adhoc.zip"

python3 - "$fixture" "$work/port" <<'PY' &
import functools, http.server, pathlib, sys
root, port_file = sys.argv[1:]
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=root)
with http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler) as server:
    pathlib.Path(port_file).write_text(str(server.server_port))
    server.serve_forever()
PY
server_pid=$!
for attempt in {1..100}; do [[ -s "$work/port" ]] && break; sleep 0.05; done
server="http://127.0.0.1:$(cat "$work/port")"
label=AppleSilicon
[[ $(uname -m) != x86_64 ]] || label=Intel
digest=$(shasum -a 256 "$fixture/new.zip")
jq -n --arg url "$server" --arg name "Nearo-1.0.1-$label.zip" --arg digest "sha256:${digest%% *}" \
  --argjson size "$(wc -c < "$fixture/new.zip")" \
  '{tag_name:"v1.0.1",draft:false,prerelease:false,html_url:$url,assets:[{name:$name,size:$size,digest:$digest,browser_download_url:($url+"/new.zip")}]}' \
  > "$fixture/latest.json"

TEST_RUNNER_NEARO_UPDATE_FIXTURE="$fixture" TEST_RUNNER_NEARO_UPDATE_SERVER="$server" \
  TEST_RUNNER_NEARO_UPDATE_FEED="$server/latest.json" \
  "${xcode[@]}" test -parallel-testing-enabled NO \
    -only-testing:NearoTests/AppVersionTests -only-testing:NearoTests/ReleaseFeedTests \
    -only-testing:NearoTests/UpdateInstallerTests
