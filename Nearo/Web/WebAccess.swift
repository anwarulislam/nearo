import AppKit
import dnssd
import Network
import Observation
import Security

/// One listener per running app, independent of the main window's lifetime.
@MainActor @Observable
final class WebAccess {
    static let preference = "nearoWebAccessEnabled"
    private static let apachePreference = "nearoUseApacheAddress"
    private(set) var configuringApache = false
    private(set) var apacheProblem: String?
    var usesApacheAddress: Bool {
        guard let domainAddress, ipAddress?.port == 8765 else { return false }
        return (domainAddress.port ?? 80) == Int(preferredPort.rawValue)
    }
    private(set) var enabled = false
    private(set) var link: URL?
    private(set) var ipAddress: URL?
    var domainAddress: URL? { link?.deletingURLFragment }
    private(set) var problem: String?
    private weak var model: NearoAppModel?
    private let defaults: UserDefaults
    private let installApache: @Sendable () async throws -> Void
    private let preferredPort: NWEndpoint.Port
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var clients: [ObjectIdentifier: NWConnection] = [:]
    private static let hostname = "nearo.local"
    @ObservationIgnored private var registration: DNSServiceRef?
    private var token = ""
    @ObservationIgnored private var routeID = ""

    init(model: NearoAppModel, defaults: UserDefaults = .standard, preferredPort: NWEndpoint.Port = .http,
         installApache: @escaping @Sendable () async throws -> Void = ApacheSetup.install) {
        self.installApache = installApache
        self.preferredPort = preferredPort
        self.model = model
        self.defaults = defaults
    }

    func restore() {
        if defaults.bool(forKey: Self.preference) { setEnabled(true) }
    }

    func setEnabled(_ value: Bool) {
        guard enabled != value || (value && problem != nil) else { return }
        stop()
        enabled = value
        defaults.set(value, forKey: Self.preference)
        guard value else { return }
        do {
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                throw WebFailure("Couldn’t create a private browser link.")
            }
            token = bytes.map { String(format: "%02x", $0) }.joined()
            routeID = UUID().uuidString
            try listen(on: preferredPort)
        } catch { failed(error) }
    }

    private func listen(on port: NWEndpoint.Port) throws {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        let server = try NWListener(using: parameters, on: port)
        listener = server
        server.newConnectionHandler = { [weak self, weak server] client in
            MainActor.assumeIsolated {
                guard let self, let server, self.listener === server, self.clients.count < 64 else {
                    client.cancel()
                    return
                }
                self.accept(client)
            }
        }
        server.stateUpdateHandler = { [weak self, weak server] state in
            MainActor.assumeIsolated {
                guard let self, let server, self.listener === server else { return }
                switch state {
                case .ready:
                    do { try self.registerHostname() } catch { self.failed(error) }
                case .failed(let error):
                    let busy = error == .posix(.EADDRINUSE) || error == .posix(.EACCES)
                    guard busy, port != .any, self.registration == nil else { self.failed(error); return }
                    server.cancel()
                    do { try self.listen(on: port == self.preferredPort && port != 8765 ? 8765 : .any) } catch { self.failed(error) }
                default: break
                }
            }
        }
        server.start(queue: .main)
    }

    private func registerHostname() throws {
        func check(_ status: DNSServiceErrorType) throws {
            if status != 0 { throw WebFailure("Couldn’t register \(Self.hostname) on this Mac (\(status)).") }
        }
        try check(DNSServiceCreateConnection(&registration))
        var record: DNSRecordRef?
        var address = in_addr(s_addr: inet_addr("127.0.0.1"))
        try check(DNSServiceRegisterRecord(registration, &record, UInt32(kDNSServiceFlagsUnique),
            kDNSServiceInterfaceIndexLocalOnly, Self.hostname + ".", UInt16(kDNSServiceType_A),
            UInt16(kDNSServiceClass_IN), UInt16(MemoryLayout.size(ofValue: address)), &address, 30,
            { connection, _, _, status, context in
                MainActor.assumeIsolated {
                    guard let context else { return }
                    let access = Unmanaged<WebAccess>.fromOpaque(context).takeUnretainedValue()
                    guard access.registration == connection, let port = access.listener?.port else { return }
                    guard status == 0 else {
                        access.failed(WebFailure("Couldn’t register nearo.local on this Mac (\(status))."))
                        return
                    }
                    let registrationID = access.routeID
                    Task { await access.publishAddresses(port: port, registrationID: registrationID) }
                }
            }, Unmanaged.passUnretained(self).toOpaque()))
        try check(DNSServiceSetDispatchQueue(registration, .main))
    }

    private static func address(_ host: String, port: NWEndpoint.Port, token: String? = nil) -> URL {
        var url = URLComponents()
        url.scheme = "http"
        url.host = host
        url.port = port == .http ? nil : Int(port.rawValue)
        url.path = "/"
        url.fragment = token
        return url.url!
    }

    private func publishAddresses(port: NWEndpoint.Port, registrationID: String, probeApache: Bool? = nil) async {
        // Probe the actual port-80 virtual host before handing the browser a private link.
        // The public routing marker is independent of the bearer token.
        var publicPort = port
        let useProxy = probeApache ?? (defaults.object(forKey: Self.apachePreference) as? Bool ?? true)
        if useProxy, port == 8765, port != preferredPort {
            let probe = Self.address("127.0.0.1", port: preferredPort).appending(path: ".well-known/nearo")
            var request = URLRequest(url: probe, timeoutInterval: 2)
            request.setValue(Self.hostname + (probe.port.map { ":\($0)" } ?? ""), forHTTPHeaderField: "Host")
            let config = URLSessionConfiguration.ephemeral
            config.connectionProxyDictionary = [:]
            config.httpShouldSetCookies = false
            config.urlCredentialStorage = nil
            let session = URLSession(configuration: config, delegate: LocalRouteProbe(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            if let (body, response) = try? await session.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200, body == Data(registrationID.utf8) {
                publicPort = preferredPort
            }
        }
        guard registrationID == routeID, listener?.port == port else { return }
        ipAddress = Self.address("127.0.0.1", port: port)
        link = Self.address(Self.hostname, port: publicPort, token: token)
    }

    func setUseApacheAddress(_ use: Bool) async {
        guard !configuringApache, enabled, let port = listener?.port, port == 8765, link != nil else { return }
        let id = routeID
        configuringApache = true
        apacheProblem = nil
        defer { configuringApache = false }
        await publishAddresses(port: port, registrationID: id, probeApache: use)
        guard routeID == id else { return }
        if use && !usesApacheAddress {
            do {
                try await installApache()
                // Apache may still be handing off connections after a graceful reload.
                for _ in 0..<8 {
                    guard routeID == id else { return }
                    await publishAddresses(port: port, registrationID: id, probeApache: true)
                    if usesApacheAddress { break }
                    try await Task.sleep(for: .milliseconds(250))
                }
                guard routeID == id else { return }
                guard usesApacheAddress else { throw WebFailure("Apache hasn’t routed nearo.local to Nearo. Your address with a port is still available.") }
            } catch is CancellationError { return }
            catch {
                if routeID == id { apacheProblem = error.localizedDescription }
                return
            }
        }
        defaults.set(use, forKey: Self.apachePreference)
    }

    isolated deinit {
        if let registration { DNSServiceRefDeallocate(registration) }
        listener?.cancel()
    }

    private func failed(_ error: Error) {
        stop()
        problem = error.localizedDescription
    }

    private func stop() {
        if let registration { DNSServiceRefDeallocate(registration) }
        registration = nil
        let old = listener
        listener = nil
        old?.cancel()
        for client in clients.values { client.cancel() }
        clients.removeAll()
        token = ""
        routeID = ""
        ipAddress = nil
        link = nil
        problem = nil
        apacheProblem = nil
    }

    private func accept(_ client: NWConnection) {
        let id = ObjectIdentifier(client)
        clients[id] = client
        client.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                switch state {
                case .cancelled, .failed: self?.clients.removeValue(forKey: id)
                default: break
                }
            }
        }
        client.start(queue: .main)
        // Bound incomplete requests, even if a client sends one byte at a time.
        let deadline = Task { @MainActor [weak client] in
            try? await Task.sleep(for: .seconds(10))
            if !Task.isCancelled { client?.cancel() }
        }
        receive(client, buffer: Data(), deadline: deadline)
    }

    private func receive(_ client: NWConnection, buffer: Data, deadline: Task<Void, Never>) {
        client.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] chunk, _, ended, error in
            MainActor.assumeIsolated {
                guard let self, self.clients[ObjectIdentifier(client)] === client, error == nil else {
                    deadline.cancel()
                    client.cancel()
                    return
                }
                var data = buffer
                if let chunk { data.append(chunk) }
                do {
                    guard let request = try WebRequest.parse(data) else {
                        if ended { deadline.cancel(); client.cancel() }
                        else { self.receive(client, buffer: data, deadline: deadline) }
                        return
                    }
                    deadline.cancel()
                    Task { @MainActor in
                        let response = await self.response(for: request)
                        guard self.clients[ObjectIdentifier(client)] === client else { return }
                        self.send(response, to: client)
                    }
                } catch {
                    deadline.cancel()
                    self.send(.error(400, "Invalid request."), to: client)
                }
            }
        }
    }

    private static let logoPNG: Data? = {
        guard let image = NSImage(named: "NearoLogo")?.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: image) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }()

    private func response(for request: WebRequest) async -> WebResponse {
        let host = request.headers["host"]?.lowercased()
        if request.method == "GET", request.path == "/.well-known/nearo",
           Self.address(Self.hostname, port: preferredPort).matchesAuthority(host), !routeID.isEmpty {
            return WebResponse(Data(routeID.utf8), mime: "text/plain")
        }
        guard let domainAddress, let ipAddress, let model else { return .error(403, "Web access is unavailable.") }
        let directDomain = Self.hostname + ":" + String(ipAddress.port ?? 80)
        if request.method == "GET", request.path == "/", !domainAddress.matchesAuthority(host),
           ipAddress.matchesAuthority(host) || host == directDomain {
            var response = WebResponse(Data())
            response.status = 302
            response.location = domainAddress
            return response
        }
        guard domainAddress.matchesAuthority(host) else { return .error(403, "Host denied.") }
        let origin = String(domainAddress.absoluteString.dropLast())
        if let source = request.headers["origin"], source != origin { return .error(403, "Origin denied.") }

        if request.method == "GET", request.path == "/nearo-logo.png" {
            guard let logo = Self.logoPNG else { return .error(500, "The Nearo logo is missing.") }
            return WebResponse(logo, mime: "image/png")
        }
        let resources = ["/": ("html", "text/html"), "/workspace.css": ("css", "text/css"),
                         "/workspace.js": ("js", "text/javascript")]
        if request.method == "GET", let (ext, mime) = resources[request.path] {
            guard let url = Bundle.main.url(forResource: "NearoWeb", withExtension: ext),
                  let data = try? Data(contentsOf: url) else { return .error(500, "Web resources are missing.") }
            return WebResponse(data, mime: mime + "; charset=utf-8")
        }
        guard !token.isEmpty, request.headers["authorization"] == "Bearer " + token else {
            return .error(401, "Open the private link in Nearo Settings.")
        }
        do {
            let api = WebWorkspace(model: model, domainAddress: domainAddress, ipAddress: ipAddress)
            switch (request.method, request.path) {
            case ("GET", "/api/state"): return try api.state(request.query)
            case ("GET", "/api/image"): return try await api.image(request.query)
            case ("POST", "/api/action"):
                guard request.headers["origin"] == origin,
                      request.headers["content-type"]?.components(separatedBy: ";").first == "application/json" else {
                    return .error(403, "Use the Nearo web interface.")
                }
                let action = try JSONDecoder().decode(WebAction.self, from: request.body)
                if action.name == "stopWeb" {
                    var result = WebResponse(Data("{}".utf8))
                    result.stopAfterSending = true
                    return result
                }
                let serving = listener
                try await api.perform(action) { self.listener === serving && self.enabled }
                return WebResponse(Data("{}".utf8))
            default: return .error(404, "Page not found.")
            }
        } catch { return .error(400, error.localizedDescription) }
    }

    private func send(_ response: WebResponse, to client: NWConnection) {
        let serving = listener
        client.send(content: response.wire, completion: .contentProcessed { [weak self] _ in
            MainActor.assumeIsolated {
                client.cancel()
                if response.stopAfterSending, let self, self.listener === serving { self.setEnabled(false) }
            }
        })
    }
}

/// An unrelated local website may redirect its unknown paths elsewhere.
private final class LocalRouteProbe: NSObject, URLSessionTaskDelegate {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                                completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private extension URL {
    var deletingURLFragment: URL? {
        var parts = URLComponents(url: self, resolvingAgainstBaseURL: false)
        parts?.fragment = nil
        return parts?.url
    }

    func matchesAuthority(_ value: String?) -> Bool {
        guard let host, let value else { return false }
        return value == "\(host):\(port ?? 80)" || (port == nil && value == host)
    }
}

struct WebFailure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

struct WebRequest {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data

    static func parse(_ data: Data) throws -> Self? {
        let invalid = WebFailure("Invalid HTTP request.")
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else {
            guard data.count < 16_384 else { throw invalid }
            return nil
        }
        guard end.lowerBound < 16_384, let head = String(data: data[..<end.lowerBound], encoding: .utf8) else { throw invalid }
        let lines = head.components(separatedBy: "\r\n")
        let start = lines[0].split(separator: " ")
        guard start.count == 3, ["GET", "POST"].contains(start[0]), start[2] == "HTTP/1.1",
              start[1].hasPrefix("/"), !start[1].hasPrefix("//"),
              var url = URLComponents(string: String(start[1])) else { throw invalid }
        var headers = [String: String]()
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { throw invalid }
            let key = line[..<colon].lowercased()
            guard !key.isEmpty, headers[key] == nil else { throw invalid }
            headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard headers["transfer-encoding"] == nil,
              let length = Int(headers["content-length"] ?? "0"), (0...131_072).contains(length) else { throw invalid }
        let present = data.count - end.upperBound
        guard present <= length else { throw invalid }
        guard present == length else { return nil }
        // URLSearchParams uses form encoding: spaces are + and an actual plus is %2B.
        url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%20")
        var query = [String: String]()
        for item in url.queryItems ?? [] { query[item.name] = item.value }
        return Self(method: String(start[0]), path: url.path, query: query, headers: headers, body: Data(data[end.upperBound...]))
    }
}

struct WebResponse {
    let data: Data
    let mime: String
    var status: Int = 200
    var stopAfterSending = false
    var location: URL?
    init(_ data: Data, mime: String = "application/json") { self.data = data; self.mime = mime }

    static func error(_ status: Int, _ message: String) -> Self {
        var result = Self((try? JSONEncoder().encode(["error": message])) ?? Data())
        result.status = status
        return result
    }

    var wire: Data {
        let reason = HTTPURLResponse.localizedString(forStatusCode: status)
        var headers = [
            "HTTP/1.1 \(status) \(reason)", "Content-Type: \(mime)", "Content-Length: \(data.count)",
            "Connection: close", "Cache-Control: no-store", "Referrer-Policy: no-referrer", "X-Content-Type-Options: nosniff",
            "Content-Security-Policy: default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' blob: data:; connect-src 'self'; frame-ancestors 'none'; form-action 'none'; base-uri 'none'"
        ]
        if let location { headers.append("Location: " + location.absoluteString) }
        return Data((headers.joined(separator: "\r\n") + "\r\n\r\n").utf8) + data
    }
}
