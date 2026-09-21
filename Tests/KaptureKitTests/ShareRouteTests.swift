import Foundation
import Testing
@testable import KaptureKit

@Suite("ShareRoute")
struct ShareRouteTests {
    private let token = ShareToken("abcdefgh12345678")

    @Test("the three paths route, and nothing else does")
    func routesThreePaths() throws {
        let token = try #require(token)

        #expect(ShareRoute.parse("/s/abcdefgh12345678") == .page(token))
        #expect(ShareRoute.parse("/s/abcdefgh12345678/strip.png") == .png(token))
        #expect(ShareRoute.parse("/s/abcdefgh12345678/strip.gif") == .gif(token))
        #expect(ShareRoute.parse("/s/abcdefgh12345678/strip.pdf") == nil)
        #expect(ShareRoute.parse("/s/abcdefgh12345678/frames/0.png") == nil)
        #expect(ShareRoute.parse("/") == nil)
        #expect(ShareRoute.parse("/favicon.ico") == nil)
    }

    /// A phone that adds a trailing slash is asking for the page, not for a
    /// fourth thing.
    @Test("a trailing slash is still the page")
    func trailingSlash() throws {
        let token = try #require(token)
        #expect(ShareRoute.parse("/s/abcdefgh12345678/") == .page(token))
    }

    /// The token is checked by shape before anything looks anything up, which
    /// is what makes a path unable to name a file.
    @Test("a path that is not a token is refused before any lookup")
    func refusesNonTokens() {
        #expect(ShareRoute.parse("/s/../recipe.json") == nil)
        #expect(ShareRoute.parse("/s/..") == nil)
        #expect(ShareRoute.parse("/s/ABCDEFGH12345678") == nil)
        #expect(ShareRoute.parse("/s/short") == nil)
        #expect(ShareRoute.parse("/s/abcdefgh1234567890") == nil)
        #expect(ShareRoute.parse("/s/abcdefgh1234567-") == nil)
    }

    @Test("a minted token is the shape the parser accepts, and two differ")
    func mintsUsableTokens() {
        let first = ShareToken.mint()
        let second = ShareToken.mint()

        #expect(first != second)
        #expect(first.value.count == ShareToken.length)
        #expect(ShareToken(first.value) == first)
    }

    /// The page links to paths this parser has to accept, so they are built
    /// from one place rather than spelled twice.
    @Test("every path a page writes parses back to the route it came from")
    func pathsRoundTrip() {
        let token = ShareToken.mint()
        for route in [ShareRoute.page(token), .png(token), .gif(token)] {
            #expect(ShareRoute.parse(ShareRoute.path(for: route)) == route)
        }
    }
}
