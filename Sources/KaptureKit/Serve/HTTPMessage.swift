import Foundation

/// The statuses this booth can answer with, named here to keep reason phrases
/// out of the call sites.
public enum HTTPStatus: Int, Equatable, Sendable {
    case ok = 200
    case badRequest = 400
    case notFound = 404
    case methodNotAllowed = 405
    case headersTooLarge = 431
    case serverError = 500

    public var reason: String {
        switch self {
        case .ok: "OK"
        case .badRequest: "Bad Request"
        case .notFound: "Not Found"
        case .methodNotAllowed: "Method Not Allowed"
        case .headersTooLarge: "Request Header Fields Too Large"
        case .serverError: "Internal Server Error"
        }
    }
}

/// What a read of a socket amounted to. Three outcomes rather than an optional:
/// "keep reading" and "this is not HTTP" need opposite responses.
public enum HTTPParse: Equatable, Sendable {
    case incomplete
    case request(HTTPRequest)
    case refused(HTTPStatus)
}

/// One request, parsed as a pure function, so the awkward half of HTTP — a
/// truncated head, a header with no colon — is tested without a socket.
public struct HTTPRequest: Equatable, Sendable {
    /// Upper-cased, because a client may send `get`.
    public let method: String
    /// Percent-decoded, and without the query.
    public let path: String
    /// Everything after the first `?`, undecoded. Nothing here reads it yet.
    public let query: String?
    /// Keyed by lower-cased name: HTTP header names are case-insensitive and a
    /// phone browser does not spell them the way a `curl` does.
    public let headers: [String: String]

    /// A head bigger than this is refused rather than buffered. Without a cap,
    /// one connection that never sends a blank line is unbounded memory.
    public static let maxHeadBytes = 8 * 1024

    public init(method: String, path: String, query: String? = nil, headers: [String: String] = [:]) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
    }

    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    public static func parse(_ head: Data) -> HTTPParse {
        guard let terminator = head.range(of: Data("\r\n\r\n".utf8)) else {
            return head.count > maxHeadBytes ? .refused(.headersTooLarge) : .incomplete
        }
        guard terminator.lowerBound <= maxHeadBytes else { return .refused(.headersTooLarge) }
        guard let text = String(data: head[..<terminator.lowerBound], encoding: .utf8) else {
            return .refused(.badRequest)
        }

        var lines = text.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return .refused(.badRequest) }
        let parts = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[2].hasPrefix("HTTP/"), parts[1].hasPrefix("/") else {
            return .refused(.badRequest)
        }

        let target = String(parts[1])
        let split = target.firstIndex(of: "?")
        let rawPath = split.map { String(target[target.startIndex..<$0]) } ?? target
        let query = split.map { String(target[target.index(after: $0)...]) }
        guard let path = rawPath.removingPercentEncoding else { return .refused(.badRequest) }

        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { return .refused(.badRequest) }
            let name = line[line.startIndex..<colon].lowercased()
            let value = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        // Nothing here reads a body, and an unread body desyncs the connection
        // on where the next request starts, so refuse rather than ignore it.
        if let length = headers["content-length"], length != "0" {
            return .refused(.badRequest)
        }
        if headers["transfer-encoding"] != nil { return .refused(.badRequest) }

        return .request(
            HTTPRequest(
                method: String(parts[0]).uppercased(),
                path: path,
                query: query,
                headers: headers
            )
        )
    }
}

/// One answer, as a value. `serialize()` is the only place bytes are made.
public struct HTTPResponse: Equatable, Sendable {
    public var status: HTTPStatus
    public var contentType: String
    public var body: Data
    /// A HEAD answer states the length of a body it does not send. Sending one
    /// anyway is the classic way to desynchronize a connection.
    public var includesBody: Bool

    public init(
        status: HTTPStatus = .ok,
        contentType: String,
        body: Data,
        includesBody: Bool = true
    ) {
        self.status = status
        self.contentType = contentType
        self.body = body
        self.includesBody = includesBody
    }

    public static func html(_ markup: String, status: HTTPStatus = .ok) -> HTTPResponse {
        HTTPResponse(
            status: status,
            contentType: "text/html; charset=utf-8",
            body: Data(markup.utf8)
        )
    }

    public static func text(_ message: String, status: HTTPStatus) -> HTTPResponse {
        HTTPResponse(
            status: status,
            contentType: "text/plain; charset=utf-8",
            body: Data("\(message)\n".utf8)
        )
    }

    /// Drops the body and keeps the length, which is what a HEAD is for.
    public func headOnly() -> HTTPResponse {
        var copy = self
        copy.includesBody = false
        return copy
    }

    public func serialize() -> Data {
        // `no-store`, not a lifetime: a phone must never hold a cached copy
        // of a strip that's since been withdrawn.
        let head = """
            HTTP/1.1 \(status.rawValue) \(status.reason)\r
            Content-Type: \(contentType)\r
            Content-Length: \(body.count)\r
            Cache-Control: no-store\r
            Connection: close\r
            \r

            """
        var data = Data(head.utf8)
        if includesBody { data.append(body) }
        return data
    }
}
