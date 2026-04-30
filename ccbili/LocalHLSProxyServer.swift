import Foundation
import Network

final class LocalHLSProxyServer {
    static let shared = LocalHLSProxyServer()

    enum RouteMode {
        case proxy
        case redirect
    }

    private let queue = DispatchQueue(label: "ccbili.local-hls-proxy")
    private let serverPort: UInt16 = 28757
    private var listener: NWListener?
    private var listenerState: NWListener.State = .setup
    private var readyContinuations: [CheckedContinuation<Void, Error>] = []
    private var routes: [String: Route] = [:]
    private var routeCounter = 0
    private var playlists: [String: String] = [:]
    private var prefetchedResponses: [String: CachedResponse] = [:]
    private var playlistCounter = 0
    private var headers: [String: String] = [:]

    private init() {}

    func resetForForegroundPlayback() throws {
        try startIfNeeded()
        queue.sync {
            routes.removeAll(keepingCapacity: true)
            playlists.removeAll(keepingCapacity: true)
            prefetchedResponses.removeAll(keepingCapacity: true)
            headers.removeAll(keepingCapacity: true)
        }
    }

    func register(mediaURL: URL, headers: [String: String], mode: RouteMode = .proxy) throws -> URL {
        try startIfNeeded()
        let id = queue.sync {
            routeCounter += 1
            let id = String(routeCounter)
            routes[id] = Route(url: mediaURL, mode: mode)
            self.headers = headers
            return id
        }
        return URL(string: "http://127.0.0.1:\(serverPort)/dash/\(id)")!
    }

    func waitUntilReady() async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                switch self.listenerState {
                case .ready:
                    continuation.resume()
                case .failed(let error):
                    continuation.resume(throwing: error)
                default:
                    self.readyContinuations.append(continuation)
                }
            }
        }
    }

    func registerPlaylist(_ content: String, name: String) throws -> URL {
        try startIfNeeded()
        let id = nextPlaylistID(name: name)
        queue.sync {
            playlists[id] = content
        }
        return URL(string: "http://127.0.0.1:\(serverPort)/hls/\(id)")!
    }

    func reservePlaylistURL(name: String) throws -> URL {
        try startIfNeeded()
        let id = nextPlaylistID(name: name)
        return URL(string: "http://127.0.0.1:\(serverPort)/hls/\(id)")!
    }

    func registerPlaylist(_ content: String, for url: URL) {
        let path = url.path
        guard path.hasPrefix("/hls/") else { return }
        let id = String(path.dropFirst("/hls/".count).split(separator: "?").first ?? "")
        queue.sync {
            playlists[id] = content
        }
    }

    func prefetch(mediaURL: URL, rangeHeader: String) {
        guard let (id, route) = routeAndID(for: mediaURL) else { return }
        Task {
            guard self.cachedResponse(id: id, rangeHeader: rangeHeader) == nil else { return }
            do {
                let (data, responseHeaders, statusCode) = try await self.fetch(route: route, id: id, rangeHeader: rangeHeader)
                self.storeCachedResponse(
                    CachedResponse(data: data, headers: responseHeaders, statusCode: statusCode),
                    id: id,
                    rangeHeader: rangeHeader
                )
            } catch {
                HLSPlaybackDiagnostics.shared.recordProxyError(
                    path: mediaURL.path,
                    requestRange: rangeHeader,
                    message: "prefetch:\(error.localizedDescription)"
                )
            }
        }
    }

    private func nextPlaylistID(name: String) -> String {
        queue.sync {
            playlistCounter += 1
            let safeName = name.replacingOccurrences(of: "/", with: "-")
            return "\(playlistCounter)-\(safeName)"
        }
    }

    private func startIfNeeded() throws {
        if listener != nil, case .ready = listenerState { return }
        if listener != nil, case .setup = listenerState { return }
        if listener != nil, case .waiting = listenerState {
            listener?.cancel()
            listener = nil
            listenerState = .setup
        }
        listener?.cancel()
        listener = nil
        listenerState = .setup
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        guard let port = NWEndpoint.Port(rawValue: serverPort) else {
            throw APIError.serverMessage("HLS 本地代理端口异常")
        }
        let listener = try NWListener(using: parameters, on: port)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            self.queue.async {
                self.listenerState = state
                if case .ready = state {
                    let continuations = self.readyContinuations
                    self.readyContinuations.removeAll()
                    continuations.forEach { $0.resume() }
                }
                if case .failed = state {
                    let continuations = self.readyContinuations
                    self.readyContinuations.removeAll()
                    continuations.forEach { $0.resume(throwing: APIError.serverMessage("HLS 本地代理启动失败")) }
                    self.listener?.cancel()
                    self.listener = nil
                }
                if case .cancelled = state {
                    self.listener = nil
                }
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        receiveNextRequest(on: connection)
    }

    private func receiveNextRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            guard let data, !data.isEmpty else {
                if isComplete || error != nil {
                    connection.cancel()
                } else {
                    self.receiveNextRequest(on: connection)
                }
                return
            }
            guard let request = String(data: data, encoding: .utf8) else {
                self.send(status: 400, body: Data(), connection: connection)
                return
            }
            Task {
                await self.respond(to: request, connection: connection)
            }
        }
    }

    private func respond(to rawRequest: String, connection: NWConnection) async {
        guard let requestLine = rawRequest.split(separator: "\r\n").first else {
            send(status: 400, body: Data(), connection: connection)
            return
        }
        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count >= 2 else {
            send(status: 400, body: Data(), connection: connection)
            return
        }

        let path = String(requestParts[1])
        if path.hasPrefix("/hls/") {
            let id = String(path.dropFirst("/hls/".count).split(separator: "?").first ?? "")
            guard let playlist = playlist(for: id) else {
                HLSPlaybackDiagnostics.shared.recordPlaylist(path: path, status: 404)
                send(status: 404, body: Data(), connection: connection)
                return
            }
            HLSPlaybackDiagnostics.shared.recordPlaylist(path: path, status: 200)
            send(
                status: 200,
                headers: [
                    "Content-Type": "application/vnd.apple.mpegurl; charset=utf-8",
                    "Cache-Control": "no-cache"
                ],
                body: Data(playlist.utf8),
                connection: connection
            )
            return
        }

        guard path.hasPrefix("/dash/") else {
            HLSPlaybackDiagnostics.shared.recordPlaylist(path: path, status: 404)
            send(status: 404, body: Data(), connection: connection)
            return
        }
        let id = String(path.dropFirst("/dash/".count).split(separator: "?").first ?? "")
        guard let route = route(for: id) else {
            send(status: 404, body: Data(), connection: connection)
            return
        }

        do {
            let rangeHeader = headerValue("Range", in: rawRequest)
            if let cachedResponse = cachedResponse(id: id, rangeHeader: rangeHeader) {
                HLSPlaybackDiagnostics.shared.recordProxy(
                    path: path,
                    requestRange: rangeHeader,
                    status: cachedResponse.statusCode,
                    responseRange: cachedResponse.headers["Content-Range"] ?? cachedResponse.headers["content-range"],
                    bytes: cachedResponse.data.count
                )
                send(
                    status: cachedResponse.statusCode,
                    headers: cachedResponse.headers,
                    body: cachedResponse.data,
                    connection: connection
                )
                return
            }

            if route.mode == .redirect {
                HLSPlaybackDiagnostics.shared.recordProxy(
                    path: path,
                    requestRange: rangeHeader,
                    status: 302,
                    responseRange: nil,
                    bytes: 0
                )
                sendRedirect(to: route.url, connection: connection)
                return
            }

            let (data, responseHeaders, statusCode) = try await fetch(route: route, id: id, rangeHeader: rangeHeader)
            HLSPlaybackDiagnostics.shared.recordProxy(
                path: path,
                requestRange: rangeHeader,
                status: statusCode,
                responseRange: responseHeaders["Content-Range"] ?? responseHeaders["content-range"],
                bytes: data.count
            )
            send(status: statusCode, headers: responseHeaders, body: data, connection: connection)
        } catch {
            HLSPlaybackDiagnostics.shared.recordProxyError(
                path: path,
                requestRange: headerValue("Range", in: rawRequest),
                message: error.localizedDescription
            )
            send(status: 502, body: Data(), connection: connection)
        }
    }

    private func fetch(route: Route, id: String, rangeHeader: String?) async throws -> (Data, [String: String], Int) {
        var request = URLRequest(url: route.url)
        request.timeoutInterval = 30
        for (key, value) in enrichedHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if let rangeHeader {
            request.setValue(rangeHeader, forHTTPHeaderField: "Range")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.serverMessage("HLS 本地代理响应异常")
        }
        var responseHeaders = [String: String]()
        for (key, value) in httpResponse.allHeaderFields {
            responseHeaders[String(describing: key)] = String(describing: value)
        }
        responseHeaders["Access-Control-Allow-Origin"] = "*"
        responseHeaders["Connection"] = "close"
        return (data, responseHeaders, httpResponse.statusCode)
    }

    private func enrichedHeaders() -> [String: String] {
        var result = queue.sync { headers }
        let cookies = HTTPCookieStorage.shared.cookies ?? []
        if let cookieHeader = HTTPCookie.requestHeaderFields(with: cookies)["Cookie"], !cookieHeader.isEmpty {
            result["Cookie"] = cookieHeader
        }
        result["Accept"] = "*/*"
        return result
    }

    private func headerValue(_ name: String, in request: String) -> String? {
        let prefix = name.lowercased() + ":"
        for line in request.split(separator: "\r\n") {
            let text = String(line)
            if text.lowercased().hasPrefix(prefix) {
                return String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func playlist(for id: String) -> String? {
        queue.sync {
            playlists[id]
        }
    }

    private func route(for id: String) -> Route? {
        queue.sync {
            routes[id]
        }
    }

    private func routeAndID(for mediaURL: URL) -> (String, Route)? {
        let path = mediaURL.path
        guard path.hasPrefix("/dash/") else { return nil }
        let id = String(path.dropFirst("/dash/".count).split(separator: "?").first ?? "")
        guard let route = route(for: id) else { return nil }
        return (id, route)
    }

    private func cachedResponse(id: String, rangeHeader: String?) -> CachedResponse? {
        guard let rangeHeader else { return nil }
        return queue.sync {
            prefetchedResponses[cacheKey(id: id, rangeHeader: rangeHeader)]
        }
    }

    private func storeCachedResponse(_ response: CachedResponse, id: String, rangeHeader: String) {
        queue.sync {
            prefetchedResponses[cacheKey(id: id, rangeHeader: rangeHeader)] = response
        }
    }

    private func cacheKey(id: String, rangeHeader: String) -> String {
        "\(id)|\(rangeHeader)"
    }

    private func send(status: Int, headers: [String: String] = [:], body: Data, connection: NWConnection) {
        var statusText = "OK"
        if status == 206 { statusText = "Partial Content" }
        if status >= 400 { statusText = "Error" }
        var headerLines = [
            "HTTP/1.1 \(status) \(statusText)",
            "Content-Length: \(body.count)",
            "Connection: keep-alive",
            "Keep-Alive: timeout=30, max=100"
        ]
        for (key, value) in headers where key.lowercased() != "content-length" && key.lowercased() != "connection" {
            headerLines.append("\(key): \(value)")
        }
        headerLines.append("")
        headerLines.append("")
        var response = Data(headerLines.joined(separator: "\r\n").utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in
            self?.receiveNextRequest(on: connection)
        })
    }

    private func sendRedirect(to url: URL, connection: NWConnection) {
        let headerLines = [
            "HTTP/1.1 302 Found",
            "Location: \(url.absoluteString)",
            "Content-Length: 0",
            "Cache-Control: no-cache",
            "Access-Control-Allow-Origin: *",
            "Connection: keep-alive",
            "Keep-Alive: timeout=30, max=100",
            "",
            ""
        ]
        let response = Data(headerLines.joined(separator: "\r\n").utf8)
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in
            self?.receiveNextRequest(on: connection)
        })
    }

    private struct Route {
        let url: URL
        let mode: RouteMode
    }

    private struct CachedResponse {
        let data: Data
        let headers: [String: String]
        let statusCode: Int
    }
}
