import Foundation
import Network

final class LocalHLSProxyServer {
    static let shared = LocalHLSProxyServer()

    private let queue = DispatchQueue(label: "ccbili.local-hls-proxy")
    private let serverPort: UInt16 = 28757
    private var listener: NWListener?
    private var routes: [String: Route] = [:]
    private var routeCounter = 0
    private var headers: [String: String] = [:]

    private init() {}

    func register(mediaURL: URL, headers: [String: String]) throws -> URL {
        try startIfNeeded()
        routeCounter += 1
        let id = String(routeCounter)
        routes[id] = Route(url: mediaURL)
        self.headers = headers
        return URL(string: "http://127.0.0.1:\(serverPort)/dash/\(id)")!
    }

    private func startIfNeeded() throws {
        if listener != nil { return }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        guard let port = NWEndpoint.Port(rawValue: serverPort) else {
            throw APIError.serverMessage("HLS 本地代理端口异常")
        }
        let listener = try NWListener(using: parameters, on: port)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                self?.send(status: 400, body: Data(), connection: connection)
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
        guard path.hasPrefix("/dash/") else {
            send(status: 404, body: Data(), connection: connection)
            return
        }
        let id = String(path.dropFirst("/dash/".count).split(separator: "?").first ?? "")
        guard let route = routes[id] else {
            send(status: 404, body: Data(), connection: connection)
            return
        }

        do {
            let rangeHeader = headerValue("Range", in: rawRequest)
            let (data, responseHeaders, statusCode) = try await fetch(route: route, rangeHeader: rangeHeader)
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

    private func fetch(route: Route, rangeHeader: String?) async throws -> (Data, [String: String], Int) {
        var request = URLRequest(url: route.url)
        request.timeoutInterval = 30
        for (key, value) in enrichedHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }
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
        var result = headers
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

    private func send(status: Int, headers: [String: String] = [:], body: Data, connection: NWConnection) {
        var statusText = "OK"
        if status == 206 { statusText = "Partial Content" }
        if status >= 400 { statusText = "Error" }
        var headerLines = [
            "HTTP/1.1 \(status) \(statusText)",
            "Content-Length: \(body.count)",
            "Connection: close"
        ]
        for (key, value) in headers where key.lowercased() != "content-length" && key.lowercased() != "connection" {
            headerLines.append("\(key): \(value)")
        }
        headerLines.append("")
        headerLines.append("")
        var response = Data(headerLines.joined(separator: "\r\n").utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private struct Route {
        let url: URL
    }
}
