import Foundation
import Network
import Testing
@testable import KaptureKit

@Suite("StripServer")
@MainActor
struct StripServerTests {
    /// A raw client rather than `URLSession`, because the bytes are the point:
    /// a session would hide a HEAD that wrongly carried a body, and would
    /// answer a 405 by throwing rather than by handing over the status line.
    private func exchange(_ request: String, port: UInt16) async throws -> String {
        let connection = NWConnection(
            host: "127.0.0.1",
            port: try #require(NWEndpoint.Port(rawValue: port)),
            using: .tcp
        )
        connection.start(queue: DispatchQueue(label: "test.client"))
        defer { connection.cancel() }

        await withCheckedContinuation { continuation in
            connection.send(
                content: Data(request.utf8),
                completion: .contentProcessed { _ in continuation.resume() }
            )
        }

        var received = Data()
        while true {
            let chunk: Data? = await withCheckedContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, _ in
                    continuation.resume(returning: data?.isEmpty == false ? data : nil)
                }
            }
            guard let chunk else { break }
            received.append(chunk)
        }
        return String(decoding: received, as: UTF8.self)
    }

    /// Echoes the path back as the body, so the test can see what the handler
    /// was given without any state shared across a concurrency boundary.
    private func echoServer() -> StripServer {
        StripServer { request in .text(request.path, status: .ok) }
    }

    @Test("a GET reaches the handler and its answer comes back whole")
    func roundTripsAGet() async throws {
        let server = echoServer()
        let port = try await server.start()
        defer { server.stop() }

        let response = try await exchange(
            "GET /s/abcdefgh12345678 HTTP/1.1\r\nHost: localhost\r\n\r\n", port: port
        )

        #expect(response.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(response.contains("Content-Length: 20\r\n"))
        #expect(response.hasSuffix("\r\n\r\n/s/abcdefgh12345678\n"))
    }

    @Test("a HEAD gets the headers and no body")
    func headHasNoBody() async throws {
        let server = echoServer()
        let port = try await server.start()
        defer { server.stop() }

        let response = try await exchange("HEAD /s/x HTTP/1.1\r\n\r\n", port: port)

        #expect(response.contains("Content-Length: 5\r\n"))
        #expect(response.hasSuffix("\r\n\r\n"))
    }

    /// Nothing here writes anything, so every other verb is refused before the
    /// handler is ever called.
    @Test("a POST is refused without reaching the handler")
    func refusesWrites() async throws {
        let server = StripServer { _ in .text("the handler ran", status: .ok) }
        let port = try await server.start()
        defer { server.stop() }

        let response = try await exchange("PUT /s/x HTTP/1.1\r\n\r\n", port: port)

        #expect(response.hasPrefix("HTTP/1.1 405 Method Not Allowed\r\n"))
        #expect(response.contains("the handler ran") == false)
    }

    @Test("a request that is not HTTP is answered and hung up on")
    func refusesGarbage() async throws {
        let server = echoServer()
        let port = try await server.start()
        defer { server.stop() }

        let response = try await exchange("hello?\r\n\r\n", port: port)

        #expect(response.hasPrefix("HTTP/1.1 400 Bad Request\r\n"))
    }

    /// Switching sharing off and on again is one toggle in the inspector, so it
    /// has to work more than once in a session.
    @Test("a stopped server starts again and answers")
    func restarts() async throws {
        let server = echoServer()
        let first = try await server.start()
        server.stop()
        #expect(server.isRunning == false)

        let second = try await server.start()
        defer { server.stop() }
        let response = try await exchange("GET /again HTTP/1.1\r\n\r\n", port: second)

        #expect(response.contains("/again"))
        #expect(first != 0 && second != 0)
    }
}
