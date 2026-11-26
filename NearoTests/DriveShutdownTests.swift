import Foundation
import Testing
@testable import Nearo

@MainActor
struct DriveShutdownTests {
    @Test func quitsImmediatelyWithoutDrives() {
        let files = PhoneFilesController(mountsEnabled: false)
        #expect(files.prepareToQuit { Issue.record("No asynchronous cleanup was needed") })
    }

    // This integration check creates a temporary loopback NFS mount on this Mac.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NEARO_TEST_DRIVE_QUIT"] == "1"))
    func quitReleasesMountedDrive() async throws {
        let files = PhoneFilesController(mountsEnabled: true)
        let id = UUID().uuidString
        let name = "Nearo shutdown test " + id
        files.update(paired: [id: name], connected: [id])
        for _ in 0..<300 where files.mountedURL(for: id) == nil && files.mountError[id] == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        let mount = try #require(files.mountedURL(for: id), "Test drive failed to mount: \(files.mountError[id] ?? "timed out")")
        #expect(PhoneMount.isMounted(mount))
        var finished = false
        #expect(!files.prepareToQuit { finished = true })
        for _ in 0..<100 where !finished { try await Task.sleep(for: .milliseconds(50)) }
        #expect(finished)
        #expect(!PhoneMount.isMounted(mount))
    }
}
