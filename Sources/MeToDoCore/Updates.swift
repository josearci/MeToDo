import Foundation

public struct ReleaseInfo: Equatable, Sendable {
    public let build: Int
    public let version: String
    public let downloadURL: URL
    public let notes: String
}

/// Reads GitHub's "latest release" answer. Releases are tagged "v1.0.<build>" by the release
/// workflow, where <build> is the commit count of main, and carry a MeToDo.zip asset.
public enum Updates {
    public static func newerRelease(in json: Data, than currentBuild: Int) -> ReleaseInfo? {
        struct Release: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: URL
            }
            let tag_name: String
            let body: String?
            let draft: Bool?
            let prerelease: Bool?
            let assets: [Asset]
        }
        guard let release = try? JSONDecoder().decode(Release.self, from: json),
              release.draft != true, release.prerelease != true,
              let build = buildNumber(fromTag: release.tag_name), build > currentBuild,
              let asset = release.assets.first(where: { $0.name == "MeToDo.zip" }),
              asset.browser_download_url.scheme == "https",
              asset.browser_download_url.host == "github.com"
        else { return nil }
        return ReleaseInfo(build: build, version: String(release.tag_name.drop(while: { $0 == "v" })),
                           downloadURL: asset.browser_download_url, notes: release.body ?? "")
    }

    /// "v1.0.42" → 42
    public static func buildNumber(fromTag tag: String) -> Int? {
        tag.drop(while: { $0 == "v" }).split(separator: ".").last.flatMap { Int($0) }
    }
}
