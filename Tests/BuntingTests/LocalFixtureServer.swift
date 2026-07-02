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

    /// Thrown by `init` when the listener never reaches `.ready`, or when the
    /// post-start self-test connection can't reach it. Surfacing this at setup
    /// time (milliseconds) beats letting every dependent test time out
    /// individually (60s each) against a server that was never actually
    /// reachable.
    struct SetupFailure: Error, CustomStringConvertible {
        let description: String
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
        //
        // Bind explicitly to the loopback interface. `.any` binds all interfaces
        // (0.0.0.0), which on GitHub Actions' macOS runners gets silently
        // dropped by the application firewall for incoming connections — the
        // client-side connect() never gets a RST, it just hangs until the
        // request times out. A loopback-scoped local endpoint avoids that path
        // entirely.
        let parameters: NWParameters = .tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        let newListener = try NWListener(using: parameters)

        let semaphore = DispatchSemaphore(value: 0)
        let stateBox = StateBox()
        newListener.stateUpdateHandler = { [stateBox] state in
            switch state {
            case .ready:
                stateBox.port = newListener.port?.rawValue ?? 0
                semaphore.signal()
            case .failed(let error):
                stateBox.failure = error
                semaphore.signal()
            default:
                break
            }
        }
        newListener.newConnectionHandler = { [routes] connection in
            connection.start(queue: .global())
            LocalFixtureServer.handle(connection: connection, routes: routes)
        }
        newListener.start(queue: queue)
        semaphore.wait()

        if let failure = stateBox.failure {
            throw SetupFailure(description: "LocalFixtureServer listener failed to start: \(failure)")
        }
        guard stateBox.port != 0 else {
            throw SetupFailure(description: "LocalFixtureServer listener reached .ready with no assigned port")
        }

        self.listener = newListener
        self.port = stateBox.port

        // Self-test: dial the port we just bound before handing the server to
        // the caller. If this hangs or fails, it means the listener is up but
        // unreachable (e.g. a runner-side firewall silently dropping incoming
        // connections) — fail fast here with a clear message instead of
        // letting every dependent test independently discover it via a 60s
        // request timeout.
        try LocalFixtureServer.selfTest(port: stateBox.port)
    }

    private static func selfTest(port: UInt16) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw SetupFailure(description: "LocalFixtureServer self-test: invalid port \(port)")
        }
        let connection = NWConnection(host: "127.0.0.1", port: nwPort, using: .tcp)
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = SelfTestResultBox()
        connection.stateUpdateHandler = { [resultBox] state in
            switch state {
            case .ready:
                resultBox.reachable = true
                semaphore.signal()
            case .failed(let error):
                resultBox.error = error
                semaphore.signal()
            default:
                break
            }
        }
        connection.start(queue: .global())
        let timedOut = semaphore.wait(timeout: .now() + 3) == .timedOut
        connection.cancel()

        if timedOut {
            throw SetupFailure(
                description:
                    "LocalFixtureServer self-test: no response connecting to 127.0.0.1:\(port) within 3s "
                    + "(listener is bound but unreachable — likely blocked by a local firewall/sandbox)")
        }
        if let error = resultBox.error {
            throw SetupFailure(
                description: "LocalFixtureServer self-test: failed to connect to 127.0.0.1:\(port): \(error)")
        }
        guard resultBox.reachable else {
            throw SetupFailure(description: "LocalFixtureServer self-test: connection to 127.0.0.1:\(port) never became ready")
        }
    }

    /// Reference box carrying the listener's post-`.ready` port or `.failed` error
    /// out of `stateUpdateHandler` without capturing `self`.
    private final class StateBox: @unchecked Sendable {
        var port: UInt16 = 0
        var failure: NWError?
    }

    /// Reference box carrying the self-test connection's outcome out of its
    /// `stateUpdateHandler` without capturing `self`.
    private final class SelfTestResultBox: @unchecked Sendable {
        var reachable = false
        var error: NWError?
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
