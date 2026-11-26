import Network
import XCTest
import WebKit
@testable import Nearo

@MainActor
final class WebAccessTests: XCTestCase {
    private func waitUntil(line: Int = #line, _ condition: () async throws -> Bool) async throws {
        for _ in 0..<100 {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw WebFailure("Timed out waiting for the browser workspace at check \(line).")
    }

    func testApacheAuthorizationRequiresExplicitSetup() async throws {
        // A different HTTP service already owns the desired port.
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        let occupied = try NWListener(using: parameters, on: .any)
        occupied.newConnectionHandler = { $0.cancel() }
        occupied.start(queue: .main)
        defer { occupied.cancel() }
        try await waitUntil { occupied.port != nil }

        actor Authorization {
            var calls = 0
            func cancel() throws { calls += 1; throw CancellationError() }
        }
        let authorization = Authorization()
        let suite = "ApacheSetupTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let model = NearoAppModel.mock()
        let access = WebAccess(model: model, defaults: defaults, preferredPort: try XCTUnwrap(occupied.port)) {
            try await authorization.cancel()
        }
        defer {
            access.setEnabled(false)
            defaults.removePersistentDomain(forName: suite)
        }
        defaults.set(true, forKey: WebAccess.preference)
        access.restore()
        try await waitUntil { access.link != nil }
        guard access.ipAddress?.port == 8765 else { throw XCTSkip("Apache backend port is in use") }
        let original = access.link
        let startupCalls = await authorization.calls
        XCTAssertEqual(startupCalls, 0)
        await access.setUseApacheAddress(true)
        let explicitCalls = await authorization.calls
        XCTAssertEqual(explicitCalls, 1)
        XCTAssertEqual(access.link, original)
        XCTAssertFalse(access.usesApacheAddress)
        XCTAssertNil(access.apacheProblem)
        await access.setUseApacheAddress(false)
        access.setEnabled(false)
        access.setEnabled(true)
        try await waitUntil { access.link != nil }
        let finalCalls = await authorization.calls
        XCTAssertEqual(finalCalls, 1)
    }

    func testBrowserTracksDeviceStateAndDispatchesActions() async throws {
        let model = NearoAppModel.mock()
        let phone = try XCTUnwrap(model.selectedDevice)
        var rings = 0
        phone.onFindPhone = { rings += 1 }
        var sentMessage: String?
        phone.onSendSMS = { _, message, _, _ in sentMessage = message }

        let suite = "NearoWebTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        // A dedicated Apache listener can exercise the reverse-proxy path in this same browser test.
        let proxyPort = ProcessInfo.processInfo.environment["NEARO_TEST_PROXY_PORT"].flatMap(UInt16.init)
        let access = WebAccess(model: model, defaults: defaults, preferredPort: proxyPort.flatMap(NWEndpoint.Port.init(rawValue:)) ?? .http) {
            throw WebFailure("The browser test must not request administrator access.")
        }
        defer {
            access.setEnabled(false)
            defaults.removePersistentDomain(forName: suite)
        }
        access.restore()
        XCTAssertFalse(access.enabled)
        access.setEnabled(true)
        try await waitUntil { access.link != nil }
        let link = try XCTUnwrap(access.link)
        let base = try XCTUnwrap(URL(string: "/", relativeTo: link)?.absoluteURL)
        XCTAssertEqual(base.host, "nearo.local")
        if let proxyPort {
            XCTAssertEqual(base.port ?? 80, Int(proxyPort))
            XCTAssertEqual(access.ipAddress?.port, 8765)
            XCTAssertTrue(access.usesApacheAddress)
            await access.setUseApacheAddress(false)
            XCTAssertEqual(access.domainAddress?.port, 8765)
            await access.setUseApacheAddress(true)
            XCTAssertEqual(access.domainAddress, base)
        }
        XCTAssertEqual(access.domainAddress, base)
        let ip = try XCTUnwrap(access.ipAddress)
        XCTAssertEqual(ip.host, "127.0.0.1")
        let (_, fromIP) = try await URLSession.shared.data(from: ip)
        XCTAssertEqual(fromIP.url, base)
        XCTAssertEqual((fromIP as? HTTPURLResponse)?.statusCode, 200)
        let (_, unauthorized) = try await URLSession.shared.data(from: base.appendingPathComponent("api/state"))
        XCTAssertEqual((unauthorized as? HTTPURLResponse)?.statusCode, 401)

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let browser = WKWebView(frame: CGRect(x: 0, y: 0, width: 1100, height: 720), configuration: configuration)
        // WebKit's page-visibility API and image loader require an attached document.
        let window = NSWindow(contentRect: browser.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = browser
        window.orderFrontRegardless()
        defer { window.close() }
        browser.load(URLRequest(url: link))
        func js(_ source: String) async throws -> Any? { try await browser.evaluateJavaScript(source) }
        try await waitUntil {
            try await js("document.querySelector('.device-description h1')?.textContent === 'Pixel 10'") as? Bool == true
        }
        try await waitUntil {
            try await js("""
                (() => {
                  const logo = document.querySelector('.sidebar-header img');
                  const toggle = document.querySelector('.sidebar-header button');
                  if (!logo?.naturalWidth || !toggle) return false;
                  const centerY = el => { const r = el.getBoundingClientRect(); return r.y + r.height / 2; };
                  return Math.abs(centerY(logo) - centerY(toggle)) <= 1
                    && !!document.querySelector('.window-title .device-status')
                    && !document.querySelector('.top-actions .connection');
                })()
                """) as? Bool == true
        }
        let clock = try await js("document.querySelector('.phone-time').textContent") as? String
        XCTAssertEqual(clock, phone.handset.time(at: .now))
        let round = try await js("""
            [...document.querySelectorAll('.native-quick .quick-icon')].every(icon =>
              icon.offsetWidth === icon.offsetHeight && getComputedStyle(icon).borderRadius === '50%')
            """) as? Bool
        XCTAssertEqual(round, true)
        let screenshot = XCTAttachment(image: try await browser.takeSnapshot(configuration: nil))
        screenshot.name = "Nearo browser overview"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        _ = try await js("document.querySelector('[data-action=ring]').click()")
        try await waitUntil { rings == 1 }

        for page in ["Messages", "Calls", "Photos", "Contacts", "Notifications", "Files", "Commands", "Settings"] {
            _ = try await js("document.querySelector('#sidebar [data-page=\(page)]').click()")
            try await waitUntil {
                try await js("document.querySelector('#content')?.dataset.view === '\(page)' && document.querySelector('#content .wrap') !== null") as? Bool == true
            }
            if ["Messages", "Contacts", "Photos", "Calls"].contains(page) {
                try await waitUntil {
                    try await js("document.querySelectorAll('#topbar #search').length === 1 && !document.querySelector('#content #search')") as? Bool == true
                }
            }
            if page == "Contacts" {
                _ = try await js("(() => { const input = document.querySelector('#topbar #search'); input.focus(); input.value = 'Anwar'; input.dispatchEvent(new Event('input', {bubbles:true})); })()")
                try await waitUntil {
                    try await js("document.activeElement.id === 'search' && document.querySelectorAll('.list-scroll .person').length === 1 && document.querySelector('.list-scroll .person').textContent.includes('Anwar')") as? Bool == true
                }
            }
            if page == "Messages" {
                _ = try await js("document.getElementById('draft').value='browser integration test'; document.getElementById('sms').requestSubmit()")
                try await waitUntil { sentMessage == "browser integration test" }
            }
            if page == "Calls" {
                try await waitUntil {
                    try await js("document.querySelector('#content .grouped')?.textContent.includes('Missed call')") as? Bool == true
                }
            }
            if page == "Photos" {
                try await waitUntil { try await js("document.querySelector('.thumb img')?.naturalWidth > 0") as? Bool == true }
            }
        }
        phone.name = "Updated phone"
        try await waitUntil { try await js("document.querySelector('.device.active b')?.textContent === 'Updated phone'") as? Bool == true }
        XCTAssertEqual(model.selectedDeviceId, phone.id)
        _ = try await js("document.querySelector('[data-device=mock_tablet]').click()")
        try await waitUntil { try await js("document.querySelector('.device-description h1')?.textContent === 'Samsung Galaxy Tab S10+'") as? Bool == true }
        XCTAssertEqual(model.selectedDeviceId, phone.id, "Browser navigation is independent of the native selection.")

        let oldToken = try XCTUnwrap(link.fragment)
        access.setEnabled(false)
        XCTAssertNil(access.link)
        XCTAssertNil(access.ipAddress)
        XCTAssertFalse(defaults.bool(forKey: WebAccess.preference))
        try await waitUntil {
            do { _ = try await URLSession.shared.data(for: URLRequest(url: ip, timeoutInterval: 2)); return false }
            catch { return true }
        }
        defaults.set(true, forKey: WebAccess.preference)
        access.restore()
        try await waitUntil { access.link != nil }
        let newLink = try XCTUnwrap(access.link)
        var request = URLRequest(url: try XCTUnwrap(URL(string: "/api/state", relativeTo: newLink)))
        request.setValue("Bearer " + oldToken, forHTTPHeaderField: "Authorization")
        let (_, expired) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((expired as? HTTPURLResponse)?.statusCode, 401)

        request = URLRequest(url: try XCTUnwrap(URL(string: "/api/action", relativeTo: newLink)))
        request.httpMethod = "POST"
        request.setValue("Bearer " + (newLink.fragment ?? ""), forHTTPHeaderField: "Authorization")
        request.setValue("https://example.invalid", forHTTPHeaderField: "Origin")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"name":"ring","device":"mock_phone"}"#.utf8)
        let (_, wrongOrigin) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((wrongOrigin as? HTTPURLResponse)?.statusCode, 403)
        XCTAssertEqual(rings, 1)

        request.httpBody = Data(#"{"name":"stopWeb"}"#.utf8)
        request.setValue("http://nearo.local" + (newLink.port.map { ":\($0)" } ?? ""), forHTTPHeaderField: "Origin")
        let (_, stopped) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((stopped as? HTTPURLResponse)?.statusCode, 200)
        try await waitUntil { !access.enabled && access.link == nil }
    }

    func testRequestReaderHandlesSplitBodiesAndBoundsHeaders() throws {
        let head = "POST /api/action HTTP/1.1\r\nHost: 127.0.0.1:9000\r\nContent-Length: 2\r\n\r\n"
        let query = "GET /api/image?id=A+B%2BC HTTP/1.1\r\nHost: 127.0.0.1:9000\r\n\r\n"
        XCTAssertEqual(try WebRequest.parse(Data(query.utf8))?.query["id"], "A B+C")
        XCTAssertNil(try WebRequest.parse(Data((head + "{").utf8)))
        XCTAssertEqual(try WebRequest.parse(Data((head + "{}").utf8))?.body, Data("{}".utf8))
        XCTAssertThrowsError(try WebRequest.parse(Data(repeating: 65, count: 20_000)))
    }
}
