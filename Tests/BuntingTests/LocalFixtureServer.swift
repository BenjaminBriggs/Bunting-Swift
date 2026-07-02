import Darwin
import Foundation

/// A minimal single-purpose HTTP/1.1 server for exercising bunting-cli's network
/// fetch path against known fixture bytes, without touching the real network.
/// Not a general-purpose server: routes are matched on exact request path,
/// each connection is handled once, and there is no keep-alive.
///
/// Deliberately built on plain POSIX/BSD sockets rather than Network.framework.
/// `NWListener` bound to loopback still accepted no connections on GitHub's
/// macOS runners (confirmed via this class's own self-test failing in exactly
/// 3s instead of tests hanging for 60s) — a framework/runner-image quirk, not
/// a bind-address problem. Raw sockets sidestep whatever Network.framework
/// layer was misbehaving there.
final class LocalFixtureServer {
    struct Response {
        let statusCode: Int
        var headers: [String: String] = [:]
        let body: Data

        static func notFound() -> Response {
            Response(statusCode: 404, body: Data("not found".utf8))
        }
    }

    /// Thrown by `init` on any socket setup failure, or when the post-start
    /// self-test connection can't reach the listener. Surfacing this at setup
    /// time (milliseconds) beats letting every dependent test time out
    /// individually (60s each) against a server that was never actually
    /// reachable.
    struct SetupFailure: Error, CustomStringConvertible {
        let description: String
    }

    private let listenSocket: Int32
    let port: UInt16
    private let routes: [String: Response]
    private let stopFlag = StopFlag()

    /// `routes` maps an exact request path (e.g. "/config.json") to the
    /// response it should receive.
    init(routes: [String: Response]) throws {
        self.routes = routes

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw SetupFailure(description: "socket() failed: \(String(cString: strerror(errno)))")
        }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0  // ephemeral; the OS assigns a free port
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            throw SetupFailure(description: "bind() to 127.0.0.1 failed: \(message)")
        }

        guard listen(fd, 16) == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            throw SetupFailure(description: "listen() failed: \(message)")
        }

        var boundAddr = sockaddr_in()
        var boundLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let getsocknameResult = withUnsafeMutablePointer(to: &boundAddr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                getsockname(fd, sockaddrPointer, &boundLen)
            }
        }
        guard getsocknameResult == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            throw SetupFailure(description: "getsockname() failed: \(message)")
        }

        self.listenSocket = fd
        self.port = UInt16(bigEndian: boundAddr.sin_port)

        let routesForAcceptLoop = routes
        let stopFlagForAcceptLoop = stopFlag
        Thread.detachNewThread { [listenSocket = fd] in
            LocalFixtureServer.acceptLoop(
                listenSocket: listenSocket, routes: routesForAcceptLoop, stopFlag: stopFlagForAcceptLoop)
        }

        // Self-test: dial the port we just bound before handing the server to
        // the caller. If this hangs or fails, the listener is up but
        // unreachable — fail fast here with a clear message instead of
        // letting every dependent test independently discover it via a 60s
        // request timeout.
        try LocalFixtureServer.selfTest(port: self.port)
    }

    func stop() {
        stopFlag.set()
        // Closing the listening socket unblocks the accept() loop's blocking
        // call on the accept thread.
        close(listenSocket)
    }

    // MARK: - Accept loop

    private static func acceptLoop(listenSocket: Int32, routes: [String: Response], stopFlag: StopFlag) {
        while stopFlag.isStopped == false {
            var clientAddr = sockaddr_in()
            var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let clientFD = withUnsafeMutablePointer(to: &clientAddr) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    accept(listenSocket, sockaddrPointer, &clientLen)
                }
            }
            if clientFD < 0 {
                // Either a transient accept() error or `stop()` closed the
                // listening socket out from under us — the loop condition
                // handles the latter on the next iteration.
                continue
            }
            Thread.detachNewThread {
                LocalFixtureServer.handleConnection(fd: clientFD, routes: routes)
            }
        }
    }

    // MARK: - Per-connection handling

    private static func handleConnection(fd: Int32, routes: [String: Response]) {
        defer { close(fd) }

        var nosigpipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))

        guard let requestText = readRequest(fd: fd),
            let requestLine = requestText.split(separator: "\r\n").first
        else {
            return
        }
        let components = requestLine.split(separator: " ")
        let path = components.count >= 2 ? String(components[1]) : "/"
        let response = routes[path] ?? Response.notFound()
        sendResponse(response, to: fd)
    }

    /// Reads from `fd` until the terminating blank line ("\r\n\r\n") of an
    /// HTTP request's headers, the connection closes, or a generous size cap
    /// is hit. Only used for header-only GET requests — no request body is
    /// read or expected.
    private static func readRequest(fd: Int32) -> String? {
        var buffer = [UInt8]()
        var chunk = [UInt8](repeating: 0, count: 4096)
        let terminator: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A]  // "\r\n\r\n"

        while buffer.count < 65536 {
            let bytesRead = chunk.withUnsafeMutableBytes { pointer -> Int in
                guard let base = pointer.baseAddress else { return 0 }
                return read(fd, base, pointer.count)
            }
            guard bytesRead > 0 else { break }
            buffer.append(contentsOf: chunk[0..<bytesRead])
            if contains(buffer, terminator) {
                break
            }
        }
        return String(bytes: buffer, encoding: .utf8)
    }

    /// Manual subsequence search — avoids relying on a specific stdlib/Foundation
    /// collection-search API being available across toolchains.
    private static func contains(_ buffer: [UInt8], _ subsequence: [UInt8]) -> Bool {
        guard buffer.count >= subsequence.count else { return false }
        let lastStart = buffer.count - subsequence.count
        for start in 0...lastStart {
            var matched = true
            for offset in 0..<subsequence.count where buffer[start + offset] != subsequence[offset] {
                matched = false
                break
            }
            if matched { return true }
        }
        return false
    }

    private static func sendResponse(_ response: Response, to fd: Int32) {
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

        payload.withUnsafeBytes { pointer in
            guard let base = pointer.baseAddress else { return }
            var totalWritten = 0
            while totalWritten < pointer.count {
                let n = write(fd, base + totalWritten, pointer.count - totalWritten)
                if n <= 0 { break }
                totalWritten += n
            }
        }
    }

    // MARK: - Self-test

    /// Dials `127.0.0.1:port` from a background thread using a plain blocking
    /// `connect()` (deliberately not Network.framework — see the type-level
    /// doc comment), with a 3s ceiling enforced via a semaphore from the
    /// calling thread.
    private static func selfTest(port: UInt16) throws {
        let resultBox = SelfTestResultBox()
        let semaphore = DispatchSemaphore(value: 0)

        Thread.detachNewThread { [resultBox] in
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else {
                resultBox.errorMessage = "socket() failed: \(String(cString: strerror(errno)))"
                semaphore.signal()
                return
            }
            defer { close(fd) }

            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")

            let connectResult = withUnsafePointer(to: &addr) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if connectResult == 0 {
                resultBox.reachable = true
            } else {
                resultBox.errorMessage = "connect() failed: \(String(cString: strerror(errno)))"
            }
            semaphore.signal()
        }

        let timedOut = semaphore.wait(timeout: .now() + 3) == .timedOut
        if timedOut {
            throw SetupFailure(
                description:
                    "LocalFixtureServer self-test: no response connecting to 127.0.0.1:\(port) within 3s "
                    + "(listener is bound but unreachable)")
        }
        if let errorMessage = resultBox.errorMessage {
            throw SetupFailure(
                description: "LocalFixtureServer self-test: failed to connect to 127.0.0.1:\(port): \(errorMessage)"
            )
        }
        guard resultBox.reachable else {
            throw SetupFailure(
                description: "LocalFixtureServer self-test: connection to 127.0.0.1:\(port) did not succeed")
        }
    }

    // MARK: - Shared state boxes

    /// Signals the accept loop to stop without requiring `self` (which isn't
    /// Sendable) to cross the thread boundary.
    private final class StopFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var stopped = false

        func set() {
            lock.lock()
            stopped = true
            lock.unlock()
        }

        var isStopped: Bool {
            lock.lock()
            defer { lock.unlock() }
            return stopped
        }
    }

    /// Reference box carrying the self-test connection's outcome out of its
    /// background thread.
    private final class SelfTestResultBox: @unchecked Sendable {
        var reachable = false
        var errorMessage: String?
    }
}
