```
 scripts/dev.sh # build + run attached to your terminal
 scripts/dev.sh --watch # + auto rebuild/restart on every save
 scripts/dev.sh --detach # old behavior (open + return)
 scripts/dev.sh --watch -NearoDemoData # flags first, app args after
```

How the terminal binding works

Instead of open (which hands the app to LaunchServices, fully detached), the script now execs the
binary — the app becomes the script process in your terminal's foreground group. Close the window →
SIGHUP → app quits. Ctrl+C → SIGINT → app quits. Verified: kill -HUP on the attached process killed
it (exit 129), and the app's stdout/stderr now stream into your terminal as a bonus.

Watch mode = hot restart, not true HMR

Being honest about the "HMR" part: compiled Swift has no mechanism to swap code into a running
process — true HMR doesn't exist for AppKit/SwiftUI. --watch gives you the next best thing: save →
detected within 1s (polling find, no fswatch dependency) → incremental rebuild → restart. Expect
~3–7s from save to relaunched app. A failed build never kills your running app, so you keep your
session while fixing the error.

Bugs the verification caught (and fixed)

1. set -e is suspended inside if build — the first watch test restarted on a stale binary after a
   failed build. Fixed with explicit || return 1 guards in build().
2. Deletions were invisible — find -newer can't see a removed file. The watcher now also compares
   the source-file count.
3. pgrep -f self-matching — a -f pattern matched my own shell's command line mid-test, sending
   osascript to quit-launch-quit a ghost instance. All process matching now uses pgrep -x Nearo (exact
   name).

Verified end-to-end

- Fail path: broken source → "Build failed — keeping the running app", same pid throughout
- Restart path: fix the source → "Change detected → Building → Restarted", new pid
- Ctrl+C teardown: watcher and app both gone, git status shows only README.md and scripts/dev.sh
  changed

One note: run it in your terminal — an app I launch from here is bound to my session, not yours.
scripts/dev.sh --watch -NearoDemoData in your shell is the intended loop.
