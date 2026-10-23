import Foundation

/// Web links in free text (task notes): http(s) URLs and bare "www." hosts.
public enum Links {
    private static let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// Each link's range (NSRange, for NSTextStorage) and the URL it opens. "www.x.com" opens http://www.x.com.
    public static func find(in text: String) -> [(range: NSRange, url: URL)] {
        let ns = text as NSString
        return detector.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            // The detector also finds emails and bare "example.com"; only take what reads as a web link.
            let written = ns.substring(with: m.range).lowercased()
            guard let url = m.url, url.scheme == "http" || url.scheme == "https",
                  ["http://", "https://", "www."].contains(where: written.hasPrefix) else { return nil }
            return (m.range, url)
        }
    }
}
