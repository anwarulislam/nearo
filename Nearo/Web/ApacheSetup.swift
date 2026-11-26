import Foundation

/// Only the native Settings action calls this installer. All privileged commands,
/// paths and configuration are fixed in the app; no browser or device data is used.
nonisolated enum ApacheSetup {
    static func install() async throws {
        try await Task.detached(priority: .userInitiated) {
            let pidFile = "/private/var/run/httpd.pid"
            guard let text = try? String(contentsOfFile: pidFile, encoding: .utf8),
                  let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 1,
                  (try? run("/bin/ps", ["-p", String(pid), "-o", "comm="])) == "/usr/sbin/httpd" else {
                throw WebFailure("This option requires the built-in Apache server to be running on this Mac.")
            }
            guard !FileManager.default.fileExists(atPath: "/private/etc/apache2/other/zz-nearo.conf") else {
                throw WebFailure("A Nearo Apache configuration already exists. Check that Apache has loaded it and forwards nearo.local to port 8765.")
            }
            let message = try run("/usr/bin/osascript", [
                "-e", "on run argv",
                "-e", "try",
                "-e", #"do shell script (item 1 of argv) with administrator privileges with prompt "Configure Apache to serve Nearo at http://nearo.local on this Mac.""#,
                "-e", "on error number -128", "-e", #"return "cancelled""#,
                "-e", "end try", "-e", "end run", command
            ])
            if message == "cancelled" { throw CancellationError() }
        }.value
    }

    private static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let message = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw WebFailure(message.isEmpty ? "Apache setup could not finish." : message)
        }
        return message
    }

    // Stage outside the *.conf include, then link without overwriting another
    // configuration. A failed syntax check or reload removes only our new file.
    private static let command = #"""
    set -eu
    export PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C
    fail() { printf '%s\n' "$1" >&2; exit 1; }
    pid=$(cat /private/var/run/httpd.pid 2>/dev/null) || fail 'The built-in Apache server is not running on this Mac.'
    [ "$(ps -p "$pid" -o comm=)" = /usr/sbin/httpd ] || fail 'Portless setup requires the built-in Apache server.'
    dir=/private/etc/apache2/other
    target=$dir/zz-nearo.conf
    [ ! -e "$target" ] && [ ! -L "$target" ] || fail 'An Apache configuration for Nearo already exists. Check that Apache has loaded it.'
    current=$(/usr/sbin/httpd -t -D DUMP_VHOSTS)
    case "$current" in *nearo.local*) fail 'Apache already defines nearo.local. Check that it forwards to 127.0.0.1:8765.' ;; esac
    stage=$(mktemp "$dir/.nearo.XXXXXXXX")
    trap 'rm -f "$stage"' EXIT
    cat > "$stage" <<'MODULES'
    <IfModule !proxy_module>
        LoadModule proxy_module libexec/apache2/mod_proxy.so
    </IfModule>
    <IfModule !proxy_http_module>
        LoadModule proxy_http_module libexec/apache2/mod_proxy_http.so
    </IfModule>
    MODULES
    # Apache uses its first virtual host for unknown names. Preserve the
    # inherited main site's behavior when Nearo is its first port-80 host.
    if ! printf '%s\n' "$current" | grep -qE '^[*]:80[[:space:]]'; then
        printf '%s\n' '<VirtualHost *:80>' '    ServerName localhost' '</VirtualHost>' >> "$stage"
    fi
    cat >> "$stage" <<'SITE'
    <VirtualHost *:80>
        ServerName nearo.local
        ProxyRequests Off
        ProxyPreserveHost On
        <Location "/">
            Require ip 127.0.0.1 ::1
        </Location>
        ProxyPass "/" "http://127.0.0.1:8765/" connectiontimeout=2 retry=0 disablereuse=On
        ProxyPassReverse "/" "http://127.0.0.1:8765/"
    </VirtualHost>
    SITE
    /usr/sbin/httpd -t -c "Include $stage"
    chmod 644 "$stage"
    ln "$stage" "$target" || fail 'Could not add the Nearo site.'
    if ! loaded=$(/usr/sbin/httpd -t -D DUMP_VHOSTS) ||
       ! printf '%s\n' "$loaded" | grep -F 'nearo.local' | grep -qF 'zz-nearo.conf:' ||
       printf '%s\n' "$loaded" | grep -q 'default server nearo.local ' ||
       ! /usr/sbin/httpd -k graceful; then
        rm -f "$target"
        fail 'Apache could not load the Nearo site. The existing configuration has been restored.'
    fi
    """#
}
