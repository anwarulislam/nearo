# Nearo size and performance

Measured on November 26, 2026, using prelaunch Nearo 1.9.1 (build 15), the launch-candidate source with the architecture walk fixtures, and Xcode 27.2 (27B52). These are local release-candidate measurements.

## Download and installed sizes

| Architecture  | DMG download | App bundle | Updater ZIP |
| ------------- | -----------: | ---------: | ----------: |
| Apple Silicon |      4.87 MB |    7.96 MB |     4.73 MB |
| Intel         |      5.07 MB |    8.06 MB |     4.92 MB |

MB uses 1,000,000 bytes. The Apple Silicon DMG contains 4,865,218 bytes and the Intel DMG contains 5,067,641. The app column sums regular-file lengths inside the signed bundle, including bundled extensions, resources and frameworks. It excludes directory metadata, symlinks and filesystem allocation overhead. The exact totals are 7,964,354 and 8,062,914 bytes respectively.

To repeat, run `scripts/release.sh` in a clean working copy, using its default local packaging mode. Read each DMG and ZIP length with `stat -f '%z' dist/Nearo-*.{dmg,zip}`. Extract the corresponding updater ZIP with `ditto -x -k` into an empty directory, then run this from that directory.

```sh
find Nearo.app -type f -exec stat -f '%z' {} + | awk '{ total += $1 } END { print total }'
lipo -archs Nearo.app/Contents/MacOS/Nearo
codesign --verify --deep --strict Nearo.app
```

Both packaged executables matched their labeled architecture. Disk-image verification, SHA-256 checks and bundle signature verification passed for both builds.

## Idle app, Apple Silicon

| Measurement                        |        Result |
| ---------------------------------- | ------------: |
| Average CPU as a share of one core |         0.80% |
| Median resident memory (RSS)       |      39.0 MiB |
| Lowest to highest sampled RSS      | 20.2–59.9 MiB |
| CPU time accrued during the sample |        0.48 s |
| Wall-clock sample interval         |       60.04 s |

The host was an 8-core MacBook Pro with an Apple M1 Pro, 16 GiB of RAM and macOS 27.0.1 (26A434). The native Release process ran in the background with its normal service startup and the 1,040 × 700 main window open on the unpaired-device screen. A fresh profile held no paired devices. The run included no transfers or user input. Other work continued on the host, including the Intel release build. Bluetooth, Tailscale discovery, mounted drives and automatic update checks were switched off. A process sandbox blocked IP networking, mDNS communication and the shared pasteboard to isolate the test from nearby devices and the Mac's live session.

For this run the benchmark used a copy of the measured Apple Silicon app with an isolated bundle identifier and a fresh ad-hoc signature. It used the release executable and standard startup path. After a 30-second warm-up, `ps -p PID -o time=,rss=` recorded the process's cumulative CPU time and resident memory once per second, from sample 0 through sample 60. CPU is the difference in cumulative CPU seconds divided by elapsed monotonic seconds, multiplied by 100. RSS is in KiB from `ps`, divided by 1,024 to report MiB.

These figures describe one offline idle run on one Mac. Connected workloads, open windows, background helpers, Intel runtime performance, and macOS memory pressure can give different results. The CPU and RSS columns cover the main Nearo process only.

### Repeat the idle sample

From the repository root with the Apple Silicon release ZIP in `dist/`, run the following in zsh. The copy and its fresh profile stay in a temporary directory. The system `sandbox-exec` utility supplies the network restrictions for this particular Mac test.

```sh
bench=$(mktemp -d)
mkdir -p "$bench/profile"
ditto -x -k dist/Nearo-1.9.1-AppleSilicon.zip "$bench"
app="$bench/Nearo.app"
plutil -replace CFBundleIdentifier -string com.anwar.nearo.benchmark.offline "$app/Contents/Info.plist"
codesign --force --deep --sign - "$app"
cat > "$bench/offline.sb" <<'PROFILE'
(version 1)
(allow default)
(deny network* (remote ip))
(deny network* (local ip))
(deny mach-lookup (global-name "com.apple.mDNSResponder") (global-name "com.apple.pasteboard.1"))
(deny network-outbound (remote unix-socket (path "/var/run/mDNSResponder")))
PROFILE
CFFIXED_USER_HOME="$bench/profile" sandbox-exec -f "$bench/offline.sb" \
  "$app/Contents/MacOS/Nearo" -nearo_bluetooth_enabled NO \
  -nearo_tailscale_discovery NO -nearo_update_automatic NO -nearo_files_enabled NO &
bench_pid=$!
sleep 30
python3 - "$bench_pid" <<'PY'
import statistics, subprocess, sys, time

start = time.monotonic()
samples = []
for index in range(61):
    time.sleep(max(0, start + index - time.monotonic()))
    cpu, rss = subprocess.check_output(
        ["ps", "-p", sys.argv[1], "-o", "time=,rss="], text=True
    ).split()
    minutes, seconds = cpu.split(":")
    samples.append((time.monotonic(), int(minutes) * 60 + float(seconds), int(rss) / 1024))

first, last = samples[0], samples[-1]
print("Average CPU (%)", 100 * (last[1] - first[1]) / (last[0] - first[0]))
print("Median RSS (MiB)", statistics.median(row[2] for row in samples))
PY
kill "$bench_pid"
```
