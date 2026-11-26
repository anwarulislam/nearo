import Network
import WebKit
import XCTest
@testable import Nearo

/// Runs the browser client against the same demonstration phone as the native gallery.
/// TEST_RUNNER_NEARO_MARKETING_DIR selects the destination and enables the capture.
@MainActor
final class WebMarketingCaptures: XCTestCase {
    func testCaptureWorkspace() async throws {
        guard let path = ProcessInfo.processInfo.environment["NEARO_MARKETING_DIR"] else {
            throw XCTSkip("Set NEARO_MARKETING_DIR to capture the browser workspace.")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "NearoBrowserCapture-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let model = NearoAppModel.mock()
        if let phone = model.selectedDevice {
            PhoneFilesController.shared.showDemoDrive(for: phone.id)
        }
        let access = WebAccess(model: model, defaults: defaults, preferredPort: .any)
        defer {
            access.setEnabled(false)
            defaults.removePersistentDomain(forName: suite)
        }
        access.setEnabled(true)
        for _ in 0..<100 where access.link == nil { try await Task.sleep(for: .milliseconds(100)) }
        let link = try XCTUnwrap(access.link, access.problem ?? "Web workspace unavailable")
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let browser = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 790), configuration: configuration)
        browser.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: browser.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = browser
        window.orderBack(nil)
        defer { window.close() }
        browser.load(URLRequest(url: link))
        for section in ["Overview", "Messages", "Calls", "Contacts", "Notifications", "Files", "Commands", "Photos"] {
            if section != "Overview" {
                _ = try await browser.evaluateJavaScript("navigate('\(section)')")
            }
            let ready = "document.title === '\(section) · Nearo' && document.querySelector('#content')?.dataset.view === '\(section)'"
            var loaded = false
            for _ in 0..<100 {
                if (try? await browser.evaluateJavaScript(ready)) as? Bool == true {
                    loaded = true
                    break
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertTrue(loaded, section)
            guard loaded else { return }
            try await Task.sleep(for: .milliseconds(900))
            let image = try await browser.takeSnapshot(configuration: nil)
            let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) })
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: directory.appendingPathComponent("web-\(section.lowercased()).png"))
        }
    }
}
