import Foundation

/// Gregorian calendar pinned to UTC so date tests don't depend on the machine's time zone.
let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

/// "2026-10-06T10:00:00Z" → Date
func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

/// A data.json path inside a fresh temporary folder (folder not created).
func tempURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("metodo-tests-\(UUID().uuidString)")
        .appendingPathComponent("data.json")
}
