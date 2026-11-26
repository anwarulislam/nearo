#!/bin/zsh
#
# Builds Nearo in Debug and runs it as part of your terminal session:
# closing the window (or Ctrl+C) quits the app with it.
#
#   scripts/dev.sh                      build and run attached
#   scripts/dev.sh -NearoDemoData       app arguments pass through
#   scripts/dev.sh --watch              rebuild + restart on source changes
#   scripts/dev.sh --build-only         build and verify the app bundle, then exit
#   scripts/dev.sh --detach             launch detached and return
#
# --watch is a hot restart, not true HMR: Swift has no way to swap freshly
# compiled code into a running process, so a save costs an incremental
# build plus a relaunch (a few seconds). A failed build never takes down
# the running app, so you can fix the error without losing your session.
#
# If a Nearo is already running (the installed release or a previous dev
# build), it is quit first: the two share a bundle id and would otherwise
# fight over the listening port and pairing.
#
# Dev builds are named "Nearo Dev" in the app menu and Dock, so they are
# easy to tell apart from the installed release.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
DERIVED="$ROOT/.build"
APP="$DERIVED/Build/Products/Debug/Nearo.app"
BINARY="$APP/Contents/MacOS/Nearo"

build_only=false
watch=false
detach=false
while [[ $# -gt 0 && "$1" == --* ]]; do
  case "$1" in
    --build-only) build_only=true ;;
    --watch)  watch=true ;;
    --detach) detach=true ;;
    --)       shift; break ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

build() {
  echo "==> Building Nearo (Debug)"
  # Explicit `|| return 1` guards throughout: inside `if build; then`,
  # `set -e` is suspended, so a failed step would otherwise fall through
  # and report success — restarting the watch loop on a stale binary.
  xcodebuild -project Nearo.xcodeproj -scheme Nearo -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
    build -quiet || return 1
  [[ -x "$BINARY" ]] || { echo "Build produced no app at $APP" >&2; return 1; }

  # Xcode's Info.plist generation forces CFBundleName to the product name
  # ("Nearo"), overriding the value in Info.plist — but CFBundleDisplayName
  # from Info.plist survives. The app menu reads CFBundleName, so copy the
  # display name over it before signing.
  plutil -replace CFBundleName \
    -string "$(plutil -extract CFBundleDisplayName raw "$APP/Contents/Info.plist")" \
    "$APP/Contents/Info.plist" || return 1

  # Ad-hoc sign the local Debug build.
  codesign --force --deep --sign - "$APP" 2>/dev/null || return 1
  codesign --verify --deep --strict "$APP" || return 1
}

# Quit a running Nearo gracefully, then fall back to a hard kill if it
# hasn't left within five seconds. Match the process name, not the path:
# a `-f` pattern would also match any shell whose command line merely
# mentions it.
quit_running() {
  pgrep -x Nearo >/dev/null 2>&1 || return 0
  echo "==> Quitting running Nearo"
  osascript -e 'tell application id "com.anwar.Nearo" to quit' >/dev/null 2>&1 || true
  for i in {1..50}; do
    pgrep -x Nearo >/dev/null 2>&1 || return 0
    sleep 0.1
  done
  pkill -x Nearo 2>/dev/null || true
}

build
if [[ "$build_only" == true ]]; then
  echo "Built $APP"
  exit 0
fi
quit_running

if [[ "$detach" == true ]]; then
  if [[ $# -gt 0 ]]; then
    open -n "$APP" --args "$@"
  else
    open -n "$APP"
  fi
  exit 0
fi

if [[ "$watch" != true ]]; then
  echo "==> Launching Nearo Dev (Ctrl+C, or closing this terminal, quits it)"
  # exec replaces the script with the app, so the signals a terminal sends
  # on close (SIGHUP) and Ctrl+C (SIGINT) land on the app itself. The app's
  # stdout/stderr stream into the terminal.
  exec "$BINARY" "$@"
fi

echo "==> Launching Nearo Dev (save a file to restart; Ctrl+C or quitting the app stops)"
MARKER="$DERIVED/.watch-stamp"
touch "$MARKER"

app_pid=0
launch() {
  "$BINARY" "$@" &
  app_pid=$!
}
launch "$@"

trap '[[ "$app_pid" -gt 0 ]] && kill "$app_pid" 2>/dev/null' EXIT
trap 'exit 0' INT TERM HUP

# Sources under Nearo/; editor swap files and dotfiles are skipped.
sources() {
  find Nearo -type f -not -name '.*' -not -name '*.swp' 2>/dev/null
}

# A change is a file newer than the marker (edits, additions) or a shift
# in the file count (deletions, which `-newer` cannot see).
last_count=$(sources | wc -l)
changed() {
  [[ -n "$(find Nearo -type f -not -name '.*' -not -name '*.swp' \
        -newer "$MARKER" -print -quit 2>/dev/null)" ]] && return 0
  [[ "$(sources | wc -l)" != "$last_count" ]]
}

while true; do
  sleep 1
  kill -0 "$app_pid" 2>/dev/null || exit 0
  changed || continue

  # Touch before building: edits made while the build runs are caught on
  # the next pass instead of chaining restarts.
  touch "$MARKER"
  last_count=$(sources | wc -l)
  echo "==> Change detected"
  if build; then
    kill "$app_pid" 2>/dev/null || true
    wait "$app_pid" 2>/dev/null || true
    app_pid=0
    quit_running
    launch "$@"
    echo "==> Restarted Nearo Dev"
  else
    echo "==> Build failed — keeping the running app" >&2
  fi
done
