import Foundation
import Network

/// A minimal single-purpose HTTP/1.1 server for exercising bunting-cli's network
/// fetch path against known fixture bytes, without touching the real network.
/// Not a general-purpose server: routes are matched on exact request path,
/// each connection is handled once, and there is no keep-alive.
final class LocalFixtureServer {
    struct Response {
        let statusCode: Int
        var headers: [String: String] = [:]
        let body: Data

        static func notFound() -> Response {
            Response(statusCode: 404, body: Data("not found".utf8))
        }
    }

    private let listener: NWListener
    let port: UInt16
    private let routes: [String: Response]
    private let queue = DispatchQueue(label: "LocalFixtureServer")

    /// `routes` maps an exact request path (e.g. "/config.json") to the
    /// response it should receive.
    init(routes: [String: Response]) throws {
        self.routes = routes
        // Build against a local variable throughout so the setup closures below
        // don't capture `self` (the class isn't Sendable, and NWListener's
        // handlers run on an arbitrary queue).
        let newListener = try NWListener(using: .tcp, on: .any)

        let semaphore = DispatchSemaphore(value: 0)
        let portBox = PortBox()
        newListener.stateUpdateHandler = { [portBox] state in
            if case .ready = state {
                portBox.value = newListener.port?.rawValue ?? 0
                semaphore.signal()
            } else if case .failed = state {
                semaphore.signal()
            }
        }
        newListener.newConnectionHandler = { [routes] connection in
            connection.start(queue: .global())
            LocalFixtureServer.handle(connection: connection, routes: routes)
        }
        newListener.start(queue: queue)
        semaphore.wait()

        self.listener = newListener
        self.port = portBox.value
    }

    /// A tiny reference box so the state-update closure can report the
    /// assigned port back without capturing `self`.
    private final class PortBox: @unchecked Sendable {
        var value: UInt16 = 0
    }

    func stop() {
        listener.cancel()
    }

    private static func handle(connection: NWConnection, routes: [String: Response]) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            data, _, _, _ in
            guard let data, let requestText = String(data: data, encoding: .utf8),
                let requestLine = requestText.split(separator: "\r\n").first
            else {
                connection.cancel()
                return
            }
            let components = requestLine.split(separator: " ")
            let path = components.count >= 2 ? String(components[1]) : "/"
            let response = routes[path] ?? Response.notFound()
            write(response: response, to: connection)
        }
    }

    private static func write(response: Response, to connection: NWConnection) {
        let statusText = response.statusCode == 200 ? "OK" : "Not Found"
        var raw = "HTTP/1.1 \(response.statusCode) \(statusText)\r\n"
        var headers = response.headers
        headers["Content-Length"] = "\(response.body.count)"
        headers["Connection"] = "close"
        for (key, value) in headers {
            raw += "\(key): \(value)\r\n"
        }
        raw += "\r\n"
        var payload = Data(raw.utf8)
        payload.append(response.body)
        connection.send(
            content: payload,
            completion: .contentProcessed { _ in
                connection.cancel()
            })
    }
}
