//
//  NearoUITests.swift
//  NearoUITests
//
//

import AppKit
import XCTest

final class NearoUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testRemoteInputWindowLocksSendsTextAndReleases() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-NearoDemoData", "-NearoDemoSection", "overview", "-workspaceTheme", "Dracula", "-workspaceAppearance", "dark"]
        app.launch()

        if !app.windows.firstMatch.waitForExistence(timeout: 2) {
            app.typeKey(",", modifierFlags: .command)
            let back = app.buttons["Back"].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 4))
            back.click()
        }
        let open = app.buttons["Remote Input"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 8))
        if let directory = ProcessInfo.processInfo.environment["NEARO_SNAPSHOT_DIR"] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("live-overview-dark.png")
            try app.windows.firstMatch.screenshot().pngRepresentation.write(to: url)
        }
        open.click()
        let window = app.windows["Remote Input"]
        let lock = window.buttons["Lock pointer"]
        XCTAssertTrue(lock.waitForExistence(timeout: 5))
        let picture = XCTAttachment(screenshot: window.screenshot())
        picture.name = "Themed Remote Input window"
        picture.lifetime = .keepAlways
        add(picture)
        lock.click()
        XCTAssertTrue(window.staticTexts["Controlling Pixel 10"].waitForExistence(timeout: 3))
        let lockedPicture = XCTAttachment(screenshot: window.screenshot())
        lockedPicture.name = "Remote Input locked"
        lockedPicture.lifetime = .keepAlways
        add(lockedPicture)
        app.typeText("Hello phone")
        XCTAssertEqual(window.textFields["Text to send"].value as? String, "Hello phone")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertEqual(window.textFields["Text to send"].value as? String, "")
        app.typeKey("x", modifierFlags: .option)
        XCTAssertTrue(lock.waitForExistence(timeout: 3))
    }

    /// Additional launch screenshots, explicitly requested with a local output directory.
    @MainActor
    func testMarketingInteractions() throws {
        guard let directory = ProcessInfo.processInfo.environment["NEARO_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set NEARO_SNAPSHOT_DIR to capture marketing interactions")
        }
        let dir = URL(fileURLWithPath: directory)
        let app = XCUIApplication()
        app.launchArguments = ["-NearoDemoData", "-NearoDemoSection", "overview", "-workspaceTheme", "Nearo",
                               "-workspaceAppearance", "light", "-nearo.receiveFolder.mock_phone",
                               NSString(string: "~/Downloads/Pixel 10").expandingTildeInPath]
        app.launch()
        if !app.windows.firstMatch.waitForExistence(timeout: 2) {
            app.typeKey(",", modifierFlags: .command)
            let back = app.buttons["Back"].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 4))
            back.click()
        }
        let window = app.windows.firstMatch
        // A neutral surface behind the app keeps the Mac's private desktop
        // and other windows out of the translucent workspace in launch assets.
        let backdrop = NSPanel(contentRect: NSScreen.main?.frame ?? .zero,
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        backdrop.backgroundColor = NSColor(srgbRed: 0.83, green: 0.86, blue: 0.89, alpha: 1)
        backdrop.ignoresMouseEvents = true
        backdrop.hidesOnDeactivate = false
        let visible = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
        if let active = NSWorkspace.shared.frontmostApplication, active.bundleIdentifier == "com.anwar.Nearo",
           let main = visible?.first(where: { $0[kCGWindowOwnerPID as String] as? Int32 == active.processIdentifier
                && $0[kCGWindowLayer as String] as? Int == 0 }),
           let id = main[kCGWindowNumber as String] as? Int {
            backdrop.order(.below, relativeTo: id)
        }
        defer { backdrop.orderOut(nil) }
        func shot(_ name: String) throws {
            try window.screenshot().pngRepresentation.write(to: dir.appendingPathComponent(name + ".png"))
        }
        let clipboard = window.buttons["Clipboard"].firstMatch
        XCTAssertTrue(clipboard.waitForExistence(timeout: 3))
        try shot("live-overview")
        clipboard.click()
        let editor = window.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText("Meet at the brick arcade before the photo walk.")
        XCTAssertEqual(editor.value as? String, "Meet at the brick arcade before the photo walk.")
        try shot("clipboard")
        window.buttons["Cancel"].firstMatch.click()

        window.buttons["Device Settings…"].click()
        XCTAssertTrue(window.buttons["Back"].waitForExistence(timeout: 4))
        try shot("live-settings-devices")
        window.buttons["Back"].click()
        for section in ["Messages", "Calls", "Contacts", "Notifications", "Files", "Commands", "Photos"] {
            window.buttons.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", section, section + ",")).firstMatch.click()
            try shot("live-" + section.lowercased())
            if section == "Messages" {
                window.buttons["New message"].firstMatch.click()
                let recipient = window.textFields["Name or phone number"]
                XCTAssertTrue(recipient.waitForExistence(timeout: 3))
                recipient.click()
                recipient.typeText("Anwar")
                try shot("live-compose")
            }
            if section == "Notifications" {
                window.links["Reply"].firstMatch.click()
                let reply = window.textFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH %@", "Reply to ")).firstMatch
                XCTAssertTrue(reply.waitForExistence(timeout: 3))
                reply.click()
                reply.typeText("I’ll bring the wide-angle lens.")
                try shot("notification-reply")
                window.buttons["Cancel"].firstMatch.click()
            }
        }
        let select = window.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Select ")).firstMatch
        XCTAssertTrue(select.waitForExistence(timeout: 3))
        let tile = select.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: -30, dy: 30))
        select.click()
        try shot("photo-selection")
        tile.click()
        XCTAssertTrue(window.buttons["Save to Downloads"].waitForExistence(timeout: 4))
        try shot("photo-preview")
    }

    @MainActor
    func testSettingsOpensInsideMainWindowAndReturnsToDevice() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-NearoDemoData"]
        app.launch()

        let window = app.windows.firstMatch
        let deviceSettings = window.buttons["Device Settings…"]
        XCTAssertTrue(deviceSettings.waitForExistence(timeout: 8))
        deviceSettings.click()
        XCTAssertTrue(window.buttons["Back"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.windows.count, 1)

        window.buttons["Back"].click()
        XCTAssertTrue(deviceSettings.waitForExistence(timeout: 3))
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(window.buttons["Back"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.windows.count, 1)

        window.buttons["Messages"].click()
        XCTAssertTrue(window.textFields["Search conversations"].waitForExistence(timeout: 3))
        XCTAssertFalse(window.buttons["Back"].exists)
    }

    @MainActor
    func testToolbarSearchFiltersContactsAndClearsWhenSwitchingSections() {
        let app = XCUIApplication()
        app.launchArguments = ["-NearoDemoData", "-NearoDemoSection", "contacts", "-workspaceTheme", "Solarized"]
        app.launch()
        let window = app.windows.firstMatch
        if !window.waitForExistence(timeout: 2) {
            app.typeKey(",", modifierFlags: .command)
            let back = window.buttons["Back"]
            XCTAssertTrue(back.waitForExistence(timeout: 4))
            back.click()
        }
        let contacts = window.buttons["Contacts"]
        if !contacts.exists && window.buttons["Show sidebar"].exists { window.buttons["Show sidebar"].click() }
        if contacts.exists { contacts.click() }
        let toolbar = window.toolbars.firstMatch
        let search = toolbar.textFields["Search contacts"]
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.click()
        search.typeText("Anwarul Islam")
        XCTAssertTrue(window.staticTexts["1 match"].waitForExistence(timeout: 3))
        let picture = XCTAttachment(screenshot: window.screenshot())
        picture.name = "Themed contact search"
        picture.lifetime = .keepAlways
        add(picture)
        window.buttons["Photos"].click()
        let photos = toolbar.textFields["Search photos"]
        XCTAssertTrue(photos.waitForExistence(timeout: 3))
        XCTAssertEqual(photos.value as? String, "")

        let searchX = photos.frame.minX
        let actionsX = toolbar.buttons["Ring phone"].frame.minX
        window.buttons["Overview"].click()
        XCTAssertTrue(toolbar.textFields.allElementsBoundByIndex.isEmpty)
        XCTAssertEqual(toolbar.buttons["Ring phone"].frame.minX, actionsX, accuracy: 1)

        for (section, prompt) in [("Calls", "Search calls"), ("Contacts", "Search contacts"), ("Messages", "Search conversations")] {
            window.buttons[section].click()
            let field = toolbar.textFields[prompt]
            XCTAssertTrue(field.waitForExistence(timeout: 3))
            XCTAssertEqual(field.frame.minX, searchX, accuracy: 1)
            XCTAssertEqual(toolbar.buttons["Ring phone"].frame.minX, actionsX, accuracy: 1)
        }
        let heading = window.staticTexts["Conversations"].firstMatch
        let title = toolbar.staticTexts["Messages"]
        XCTAssertTrue(heading.exists)
        XCTAssertTrue(title.exists)
        XCTAssertEqual(title.frame.minX, heading.frame.minX, accuracy: 1)
        let messages = XCTAttachment(screenshot: window.screenshot())
        messages.name = "Messages column alignment"
        messages.lifetime = .keepAlways
        add(messages)
        let expandedX = title.frame.minX
        toolbar.buttons["Hide sidebar"].click()
        XCTAssertTrue(toolbar.buttons["Show sidebar"].waitForExistence(timeout: 3))
        XCTAssertLessThan(title.frame.minX, expandedX)
        toolbar.buttons["Show sidebar"].click()
        XCTAssertEqual(title.frame.minX, heading.frame.minX, accuracy: 1)
    }

    @MainActor
    func testMenuDeviceHeaderOpensDisplayedPhoneFromSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["-NearoDemoData"]
        app.launch()
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.windows.firstMatch.buttons["Back"].waitForExistence(timeout: 4))
        let statusItem = app.descendants(matching: .statusItem).firstMatch
        statusItem.click()
        let choose = app.buttons["Devices, Pixel 10"].firstMatch
        XCTAssertTrue(choose.waitForExistence(timeout: 3))
        choose.click()
        XCTAssertFalse(choose.exists)
        app.typeKey(.escape, modifierFlags: [])
        app.buttons["Open Pixel 10 in Nearo"].firstMatch.click()
        XCTAssertTrue(app.windows.firstMatch.buttons["Device Settings…"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testSystemAppearanceFollowsMacAfterManualOverride() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-NearoDemoData"]
        app.launch()
        app.typeKey(",", modifierFlags: .command)
        let window = app.windows.firstMatch
        window.buttons["Themes"].click()
        let choices = window.radioButtons
        let original = try XCTUnwrap(choices.allElementsBoundByIndex.first {
            ($0.value as? NSNumber)?.boolValue == true || $0.value as? String == "1"
        })
        defer { original.click() }

        let systemIsDark = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let manual = choices[systemIsDark ? "Light" : "Dark"]
        func brightness() throws -> Double {
            let image = try XCTUnwrap(NSBitmapImageRep(data: window.screenshot().pngRepresentation))
            let color = try XCTUnwrap(image.colorAt(x: image.pixelsWide / 2, y: 12)?.usingColorSpace(.deviceRGB))
            return Double(color.redComponent + color.greenComponent + color.blueComponent) / 3
        }
        manual.click()
        let overridden = try brightness()
        choices["System"].click()
        let restored = try brightness()
        XCTAssertGreaterThan(systemIsDark ? overridden - restored : restored - overridden, 0.2)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
