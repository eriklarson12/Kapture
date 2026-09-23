import Foundation
import Network

public enum StripServerError: Error, Equatable {
    case startFailed(String)
    case noPort
}

/// A one-connection-at-a-time HTTP/1.1 server for handing a strip to a phone.
/// Parsing, routing and the page are tested values elsewhere; this is just the thin socket layer.
@MainActor
public final class StripServer {
    public typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse

    /// The port the listener actually got, which is only known once it is up.
    public private(set) var port: UInt16?

    private let handle: Handler
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.eriklarson.kapture.server")

    public init(handle: @escaping Handler) {
        self.handle = handle
    }

    public var isRunning: Bool { listener != nil }

    /// Starts on an ephemeral port and waits until actually listening. Nothing
    /// to configure or collide with — the QR code doesn't care what the number is.
    @discardableResult
    public func start() async throws -> UInt16 {
        if let port { return port }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: .any)
        } catch {
            throw StripServerError.startFailed(error.localizedDescription)
        }

        let handle = self.handle
        let queue = self.queue
        listener.newConnectionHandler = { connection in
            Task { await Self.serve(connection, on: queue, handle: handle) }
        }

        do {
            let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
                let gate = Gate(continuation)
                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        if let port = listener.port?.rawValue {
                            gate.finish(.success(port))
                        } else {
                            gate.finish(.failure(StripServerError.noPort))
                        }
                    case .failed(let error), .waiting(let error):
                        gate.finish(
                            .failure(StripServerError.startFailed(error.localizedDescription))
                        )
                    default:
                        break
                    }
                }
                listener.start(queue: queue)
            }
            self.listener = listener
            self.port = port
            return port
        } catch {
            listener.cancel()
            throw error
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        port = nil
    }

    private static func serve(
        _ connection: NWConnection, on queue: DispatchQueue, handle: Handler
    ) async {
        connection.start(queue: queue)
        defer { connection.cancel() }

        var head = Data()
        while true {
            switch HTTPRequest.parse(head) {
            case .request(let request):
                await send(answer(to: request, handle: handle), over: connection)
                return
            case .refused(let status):
                await send(.text(status.reason, status: status), over: connection)
                return
            case .incomplete:
                guard let chunk = await receive(connection) else { return }
                head.append(chunk)
            }
        }
    }

    /// GET and HEAD only. HEAD still runs the handler so its reported length
    /// matches what a GET would actually send.
    private static func answer(to request: HTTPRequest, handle: Handler) async -> HTTPResponse {
        switch request.method {
        case "GET": await handle(request)
        case "HEAD": await handle(request).headOnly()
        default: .text(HTTPStatus.methodNotAllowed.reason, status: .methodNotAllowed)
        }
    }

    private static func receive(_ connection: NWConnection) async -> Data? {
        await withCheckedContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                continuation.resume(returning: data?.isEmpty == false ? data : nil)
            }
        }
    }

    private static func send(_ response: HTTPResponse, over connection: NWConnection) async {
        await withCheckedContinuation { continuation in
            connection.send(
                content: response.serialize(),
                isComplete: true,
                completion: .contentProcessed { _ in continuation.resume() }
            )
        }
    }
}

/// Resumes a continuation exactly once. `stateUpdateHandler` can report ready
/// then failed, and a continuation resumed twice traps (ADR-009).
private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<UInt16, Error>?

    init(_ continuation: CheckedContinuation<UInt16, Error>) {
        self.continuation = continuation
    }

    func finish(_ result: Result<UInt16, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}
