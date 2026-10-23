import Testing
import Foundation
@testable import MeToDoCore

@Suite struct LinksTests {
    /// (text the link covers, URL it opens) for each link found.
    func links(_ text: String) -> [String] {
        Links.find(in: text).map { "\((text as NSString).substring(with: $0.range)) → \($0.url.absoluteString)" }
    }

    @Test func httpsURLInNotes() {
        #expect(links("ClickUp (Sprint 22): https://app.clickup.com/t/10637855/868m3waaa")
            == ["https://app.clickup.com/t/10637855/868m3waaa → https://app.clickup.com/t/10637855/868m3waaa"])
    }

    @Test func bareWWWOpensOverHTTP() {
        #expect(links("see www.example.com for more") == ["www.example.com → http://www.example.com"])
    }

    @Test func severalLinksAndTrailingPunctuation() {
        #expect(links("A http://a.com/x, then (https://b.org/y).\nDone.")
            == ["http://a.com/x → http://a.com/x", "https://b.org/y → https://b.org/y"])
    }

    @Test func emailsBareDomainsAndOtherSchemesAreNotLinks() {
        #expect(links("mail ana@example.com, visit example.com, ftp://files.example.com, plain text").isEmpty)
    }

    @Test func rangesAreUTF16ForEmojiText() {
        let text = "🎓 Inglés: https://x.com/é"
        let found = Links.find(in: text)
        #expect(found.count == 1)
        #expect((text as NSString).substring(with: found[0].range).hasPrefix("https://x.com/"))
    }
}
