import Foundation
import Testing
@testable import KaptureKit

@Suite("SharePage")
struct SharePageTests {
    private let token = ShareToken.mint()

    @Test("the page links to both files, by token")
    func linksBothFiles() {
        let html = SharePage.html(token: token, caption: nil)

        #expect(html.contains("/s/\(token.value)/strip.png"))
        #expect(html.contains("/s/\(token.value)/strip.gif"))
    }

    /// A caption is the first user text in this project that becomes markup.
    @Test("a caption that looks like markup comes out as text")
    func escapesCaption() {
        let html = SharePage.html(token: token, caption: "<script>alert('x')</script>")

        #expect(html.contains("<script>") == false)
        #expect(html.contains("&lt;script&gt;"))
        #expect(html.contains("&#39;x&#39;"))
    }

    /// Ampersand first, or everything written after it is escaped twice and
    /// the page shows `&amp;lt;`.
    @Test("an ampersand is escaped once")
    func escapesAmpersandOnce() {
        #expect(SharePage.escaped("Ben & Ada <3") == "Ben &amp; Ada &lt;3")
        #expect(SharePage.escaped("\"quoted\"") == "&quot;quoted&quot;")
    }

    @Test("no caption means no caption line")
    func omitsEmptyCaption() {
        #expect(SharePage.html(token: token, caption: nil).contains("class=\"caption\"") == false)
        #expect(SharePage.html(token: token, caption: "   ").contains("class=\"caption\"") == false)
        #expect(SharePage.html(token: token, caption: "Hi").contains("class=\"caption\">Hi<"))
    }

    /// Without the viewport line a phone renders the page at desktop width and
    /// the strip arrives two millimetres wide.
    @Test("the page declares its encoding and a phone viewport")
    func declaresEncodingAndViewport() {
        let html = SharePage.html(token: token, caption: nil)

        #expect(html.contains("<meta charset=\"utf-8\">"))
        #expect(html.contains("name=\"viewport\""))
        #expect(html.hasPrefix("<!DOCTYPE html>"))
    }

    /// The normal end of every link, so it has to read like an explanation.
    @Test("a withdrawn link gets a page saying so, and no links")
    func gonePage() {
        let html = SharePage.gone()

        #expect(html.contains("That strip has gone."))
        #expect(html.contains("/s/") == false)
        #expect(html.contains("<img") == false)
    }
}
