import Foundation

/// Reads and writes data.json. Never overwrites a file it couldn't read.
public struct Persistence: Sendable {
    public enum LoadResult: Sendable {
        case fresh(AppData)
        case loaded(AppData)
        /// The file was unreadable. `movedTo` is where it was preserved; nil means it
        /// couldn't be moved, so the caller must not save over it.
        case corrupt(AppData, movedTo: URL?)
    }

    public let url: URL

    public init(url: URL) { self.url = url }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeToDo")
            .appendingPathComponent("data.json")
    }

    var backupURL: URL { url.appendingPathExtension("bak") }

    public func load(now: Date = Date()) -> LoadResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return .fresh(.fresh()) }
        do {
            let data = try JSONDecoder.metodo.decode(AppData.self, from: Data(contentsOf: url))
            try? fm.removeItem(at: backupURL)
            try? fm.copyItem(at: url, to: backupURL)
            return .loaded(data)
        } catch {
            let stamp = Self.stamp.string(from: now)
            let dest = url.deletingLastPathComponent().appendingPathComponent("data-corrupt-\(stamp).json")
            do {
                try fm.moveItem(at: url, to: dest)
                return .corrupt(.fresh(), movedTo: dest)
            } catch {
                return .corrupt(.fresh(), movedTo: nil)
            }
        }
    }

    public func save(_ data: AppData) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.metodo.encode(data).write(to: url, options: .atomic)
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()
}

extension JSONEncoder {
    static var metodo: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    static var metodo: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
