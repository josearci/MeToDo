import Testing
import Foundation
@testable import MeToDoCore

@Suite struct UpdatesTests {
    func release(tag: String = "v1.0.42", asset: String = "MeToDo.zip",
                 url: String = "https://github.com/josearci/MeToDo/releases/download/v1.0.42/MeToDo.zip",
                 draft: Bool = false, prerelease: Bool = false) -> Data {
        Data("""
        {"tag_name":"\(tag)","draft":\(draft),"prerelease":\(prerelease),"body":"Notes",
         "assets":[{"name":"\(asset)","browser_download_url":"\(url)"}]}
        """.utf8)
    }

    @Test func newerReleaseIsOffered() throws {
        let r = try #require(Updates.newerRelease(in: release(), than: 41))
        #expect(r.build == 42)
        #expect(r.version == "1.0.42")
        #expect(r.downloadURL.absoluteString.hasSuffix("/MeToDo.zip"))
        #expect(r.notes == "Notes")
    }

    @Test func sameOrOlderIsNotOffered() {
        #expect(Updates.newerRelease(in: release(), than: 42) == nil)
        #expect(Updates.newerRelease(in: release(), than: 50) == nil)
    }

    @Test func unsafeOrIncompleteReleasesAreIgnored() {
        #expect(Updates.newerRelease(in: release(asset: "Other.zip"), than: 1) == nil)
        #expect(Updates.newerRelease(in: release(url: "http://github.com/x/MeToDo.zip"), than: 1) == nil)
        #expect(Updates.newerRelease(in: release(url: "https://evil.example.com/MeToDo.zip"), than: 1) == nil)
        #expect(Updates.newerRelease(in: release(draft: true), than: 1) == nil)
        #expect(Updates.newerRelease(in: release(prerelease: true), than: 1) == nil)
        #expect(Updates.newerRelease(in: Data("not json".utf8), than: 1) == nil)
        #expect(Updates.newerRelease(in: release(tag: "latest"), than: 1) == nil)
    }

    @Test(arguments: [("v1.0.42", 42), ("1.0.7", 7), ("v2", 2), ("nightly", nil)])
    func buildNumberFromTag(_ tag: String, _ expected: Int?) {
        #expect(Updates.buildNumber(fromTag: tag) == expected)
    }
}
