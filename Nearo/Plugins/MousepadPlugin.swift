//
//  MousepadPlugin.swift
//  Nearo
//
//  Remote input plugin for touchpad, clicks, scrolling, and keyboard input.
//

import Foundation

public final class MousepadPlugin: NearoPlugin, @unchecked Sendable {
    public static let requestType = "kdeconnect.mousepad.request"
    public static let keyboardStateType = "kdeconnect.mousepad.keyboardstate"
    public static let echoType = "kdeconnect.mousepad.echo"

    static func request(body: [String: Any]) -> NetworkPacket {
        var fields = body
        // Android reads an absent specialKey as -1 and skips ordinary text input.
        if fields["key"] != nil && fields["specialKey"] == nil { fields["specialKey"] = 0 }
        return NetworkPacket(type: requestType, body: fields)
    }

    public var supportedPacketTypes: [String] {
        [Self.requestType]
    }

    private let textFocus = RemoteTextFocus()
    private var watchers: [ObjectIdentifier: (DeviceConnection, String)] = [:]

    public init() {
        textFocus.onChange = { [weak self] token in
            guard let self else { return }
            for (connection, session) in watchers.values {
                sendFocus(token, session: session, to: connection)
            }
        }
    }

    private func sendFocus(_ token: String, session: String, to connection: DeviceConnection) {
        connection.send(packet: NetworkPacket(type: Self.keyboardStateType, body: [
            "state": true, "nearoFocusToken": token, "nearoSession": session
        ]))
    }

    public func onConnected(connection: DeviceConnection) {
        // Announce that we support keyboard input
        let packet = NetworkPacket(
            type: Self.keyboardStateType,
            body: ["state": true, "nearoFocusSupport": true]
        )
        connection.send(packet: packet)
        NearoLog("[MousepadPlugin] Sent keyboardstate {state: true} to \(connection.peerDeviceInfo?.deviceName ?? "device")")
    }

    public func onDisconnected(connection: DeviceConnection) {
        watchers.removeValue(forKey: ObjectIdentifier(connection))
        if watchers.isEmpty { textFocus.stop() }
    }

    public func handlePacket(connection: DeviceConnection, packet: NetworkPacket) {
        guard packet.type == Self.requestType else { return }

        if packet.has("nearoWatchTextFocus") {
            guard let session = packet.string(for: "nearoSession"), !session.isEmpty else { return }
            let id = ObjectIdentifier(connection)
            if packet.bool(for: "nearoWatchTextFocus") {
                textFocus.start()
                watchers[id] = (connection, session)
                sendFocus(textFocus.token, session: session, to: connection)
            } else if watchers[id]?.1 == session {
                onDisconnected(connection: connection)
            }
            return
        }

        // Synthesize input event
        InputSynthesizer.shared.handlePacket(packet)

        // Send ack if requested
        if packet.bool(for: "sendAck") == true {
            let echo = NetworkPacket(
                type: Self.echoType,
                body: ["isAck": AnyCodable(true)]
            )
            connection.send(packet: echo)
        }
    }
}
