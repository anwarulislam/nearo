import Foundation

nonisolated enum ReceiveFolder {
    static var defaultURL: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    static func preferenceKey(for deviceID: String) -> String {
        "nearo.receiveFolder.\(deviceID)"
    }

    static func url(for deviceID: String) -> URL {
        guard let path = UserDefaults.standard.string(forKey: preferenceKey(for: deviceID)) else {
            return defaultURL
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
