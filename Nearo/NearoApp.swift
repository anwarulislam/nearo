//
//  NearoApp.swift
//  Nearo
//

import SwiftUI

@MainActor
final class NearoAppDelegate: NSObject, NSApplicationDelegate {
    var menuModel: NearoAppModel?
    var mainWindowAction: OpenWindowAction?
    private var widgetPublisher: DeviceWidgetPublisher?
    private var statusMenu: StatusMenuController?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let menuModel {
            widgetPublisher = DeviceWidgetPublisher(model: menuModel)
            statusMenu = StatusMenuController(model: menuModel) { [weak self] in self?.mainWindowAction?(id: "main") }
            NearoControlSession.showPanel = { [weak self] page in self?.statusMenu?.show(page) ?? false }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { widgetPublisher?.stopped() }

    /// Finish drive work before a menu action enters AppKit’s modal termination loop.
    static func quit() {
        if PhoneFilesController.shared.prepareToQuit(completion: { NSApp.terminate(nil) }) {
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let ready = PhoneFilesController.shared.prepareToQuit { sender.reply(toApplicationShouldTerminate: true) }
        return ready ? .terminateNow : .terminateLater
    }
}

@main
struct NearoApp: App {
    @NSApplicationDelegateAdaptor(NearoAppDelegate.self) private var delegate
    @AppStorage("workspaceAppearance") private var appearance = WorkspaceAppearance.system
    @State private var appModel: NearoAppModel
    @Environment(\.openWindow) private var openWindow

    init() {
        #if DEBUG
        // `-NearoDemoData` fills the UI with sample devices for screenshots and
        // design work, without touching the network.
        // `-NearoDemoRinging` also shows the Ring panel, without sound.
        // `-NearoDemoCall` also shows the incoming-call card.
        let isDemo = ProcessInfo.processInfo.arguments.contains("-NearoDemoData")
        if isDemo {
            let demo = NearoAppModel.mock()
            _appModel = State(initialValue: demo)
            delegate.menuModel = demo
            NearoControlSession.model = demo
            demo.webAccess.restore()
            PhoneFilesController.shared.showDemoDrive(for: "mock_phone")
            if ProcessInfo.processInfo.arguments.contains("-NearoDemoRinging") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    MacRinger.shared.showDemoPanel(deviceName: DemoDevices.phone)
                }
            }
            if ProcessInfo.processInfo.arguments.contains("-NearoDemoCall") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    CallCard.shared.showDemo()
                }
            }
            return
        }
        #endif

        _appModel = State(initialValue: .shared)

        // Unit tests run inside a copy of the app. Starting the services there
        // would connect to the phone next to the real Nearo and unmount its
        // phone drive as a "leftover".
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }

        delegate.menuModel = .shared
        NearoControlSession.model = .shared

        // Eagerly initialize identity on main thread
        _ = DeviceIdentity.shared
        // Start background discovery and network services
        NearoService.shared.start()
        // Receive what's shared from the Share menu
        ShareInbox.shared.start()
        // Look for a newer release once a day
        UpdateController.shared.start()
        // Serve the phone's storage to Finder
        PhoneFilesController.shared.start()
        NearoAppModel.shared.webAccess.restore()
    }

    /// Demo data opens the main window at `-NearoDemoSection <section>`
    /// (overview when not given).
    private static var demoSection: DeviceSection? {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-NearoDemoData") else { return nil }
        let key = UserDefaults.standard.string(forKey: "NearoDemoSection")
        return key.flatMap(DeviceSection.init) ?? .overview
        #else
        return nil
        #endif
    }

    var body: some Scene {
        mainWindow
        WindowGroup("Remote Input", id: "remote-input", for: String.self) { $deviceID in
            if let device = appModel.allDevices.first(where: { $0.id == deviceID }) {
                RemoteInputView(device: device)
            } else {
                ContentUnavailableView("Device unavailable", systemImage: "iphone.slash")
            }
        }
        .defaultSize(width: 590, height: 470)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultLaunchBehavior(.suppressed)
        .commandsRemoved()
    }

    private var mainWindow: some Scene {
        // The AppKit status panel uses the same SwiftUI scene even after its last window closes.
        delegate.mainWindowAction = openWindow
        return Window("Nearo", id: "main") {
            MainWindowView(appModel: appModel, initialSection: Self.demoSection ?? .overview)
                .nearoMotionPreference()
        }
        .defaultSize(width: 1040, height: 700)
        .defaultLaunchBehavior(Self.demoSection == nil ? .automatic : .presented)
        .windowToolbarStyle(.unified(showsTitle: false))
        .onChange(of: appearance, initial: true) { NSApp.appearance = appearance.appKitAppearance }
        .commands {
            NearoCommands(appModel: appModel)
        }

    }
}
