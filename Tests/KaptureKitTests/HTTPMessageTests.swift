import Foundation
import Testing
@testable import KaptureKit

@Suite("HTTPMessage")
struct HTTPMessageTests {
    private func head(_ text: String) -> Data { Data(text.utf8) }

    @Test("a plain GET parses into its method, path and headers")
    func parsesGet() {
        let parsed = HTTPRequest.parse(head("GET /s/abc HTTP/1.1\r\nHost: 10.0.0.4:8080\r\n\r\n"))

        guard case .request(let request) = parsed else {
            Issue.record("expected a request, got \(parsed)")
            return
        }
        #expect(request.method == "GET")
        #expect(request.path == "/s/abc")
        #expect(request.query == nil)
        #expect(request.header("Host") == "10.0.0.4:8080")
    }

    /// A phone sends `Accept-Encoding`, a curl sends `accept-encoding`, and the
    /// RFC says they are the same header.
    @Test("header names are matched without case")
    func headersIgnoreCase() {
        let parsed = HTTPRequest.parse(head("get /x HTTP/1.1\r\nACCEPT: text/html\r\n\r\n"))

        guard case .request(let request) = parsed else {
            Issue.record("expected a request")
            return
        }
        #expect(request.method == "GET")
        #expect(request.header("accept") == "text/html")
    }

    @Test("a query is split off, and the path is percent-decoded")
    func splitsQueryAndDecodes() {
        let parsed = HTTPRequest.parse(head("GET /a%20b/c?x=1&y=2 HTTP/1.1\r\n\r\n"))

        guard case .request(let request) = parsed else {
            Issue.record("expected a request")
            return
        }
        #expect(request.path == "/a b/c")
        #expect(request.query == "x=1&y=2")
    }

    /// The difference that matters: this one means "read more", not "give up".
    @Test("a head with no blank line is incomplete rather than wrong")
    func incompleteHead() {
        #expect(HTTPRequest.parse(head("GET / HTTP/1.1\r\nHost: x\r\n")) == .incomplete)
    }

    @Test("a request line that is not three tokens is refused")
    func malformedRequestLine() {
        #expect(HTTPRequest.parse(head("GET\r\n\r\n")) == .refused(.badRequest))
        #expect(HTTPRequest.parse(head("GET /x /y HTTP/1.1\r\n\r\n")) == .refused(.badRequest))
    }

    @Test("a target that is not a path is refused")
    func refusesAbsoluteTarget() {
        #expect(
            HTTPRequest.parse(head("GET http://elsewhere/ HTTP/1.1\r\n\r\n"))
                == .refused(.badRequest)
        )
    }

    @Test("a header line with no colon is refused")
    func refusesHeaderWithoutColon() {
        #expect(HTTPRequest.parse(head("GET / HTTP/1.1\r\nnonsense\r\n\r\n")) == .refused(.badRequest))
    }

    /// Without the cap, one client that never sends a blank line is unbounded
    /// memory on the booth.
    @Test("a head over the cap is refused rather than buffered")
    func refusesOversizedHead() {
        let padding = String(repeating: "x", count: HTTPRequest.maxHeadBytes + 1)
        #expect(
            HTTPRequest.parse(head("GET / HTTP/1.1\r\nPad: \(padding)\r\n"))
                == .refused(.headersTooLarge)
        )
    }

    /// Nothing reads a body, and a body left on the wire is a connection that
    /// disagrees with its client about where the next request starts.
    @Test("a request carrying a body is refused")
    func refusesBody() {
        #expect(
            HTTPRequest.parse(head("POST / HTTP/1.1\r\nContent-Length: 4\r\n\r\n"))
                == .refused(.badRequest)
        )
        #expect(
            HTTPRequest.parse(head("POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"))
                == .refused(.badRequest)
        )
    }

    @Test("a response serializes its status line, headers, blank line and body")
    func serializesResponse() {
        let response = HTTPResponse.text("Not Found", status: .notFound)
        let text = String(decoding: response.serialize(), as: UTF8.self)

        #expect(text == """
            HTTP/1.1 404 Not Found\r
            Content-Type: text/plain; charset=utf-8\r
            Content-Length: 10\r
            Cache-Control: no-store\r
            Connection: close\r
            \r
            Not Found

            """)
    }

    /// A HEAD states the length of a body it does not send. Sending one anyway
    /// is the classic way to desynchronize a connection.
    @Test("a HEAD answer keeps the length and drops the body")
    func headOnlyKeepsLength() {
        let body = Data(repeating: 0x41, count: 40)
        let response = HTTPResponse(contentType: "image/png", body: body).headOnly()
        let text = String(decoding: response.serialize(), as: UTF8.self)

        #expect(text.contains("Content-Length: 40\r\n"))
        #expect(text.hasSuffix("\r\n\r\n"))
    }

    @Test("every answer forbids caching")
    func neverCached() {
        let text = String(decoding: HTTPResponse.html("<p>x</p>").serialize(), as: UTF8.self)
        #expect(text.contains("Cache-Control: no-store\r\n"))
    }
}
