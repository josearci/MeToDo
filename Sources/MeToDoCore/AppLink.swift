import Foundation
import CryptoKit

/// How `metodo` and the running app share data.json without overwriting each other.
///
/// The app takes an exclusive lock on `data.json.lock` before it loads the data and keeps it until it
/// exits (the OS drops it even on a crash), and answers CLI requests over a Mach message port. The CLI
/// only reads or writes data.json itself while it holds that same lock, i.e. when no app is running;
/// otherwise it hands its arguments to the app, which runs them on its live Store and saves.
public struct AppLink: Sendable {
    public let persistence: Persistence

    public init(persistence: Persistence) { self.persistence = persistence }

    var lockURL: URL { persistence.url.appendingPathExtension("lock") }

    /// One per data file, so a CLI pointed at test data never talks to the app that has the real data.
    var portName: String {
        let path = persistence.url.standardizedFileURL.resolvingSymlinksInPath().path
        let hash = SHA256.hash(data: Data(path.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return "com.josearci.metodo.cli.\(hash)"
    }

    /// Takes the lock, retrying for up to `timeout` seconds. Returns the descriptor holding it
    /// (closing it, or exiting, releases the lock), or nil if someone else still has it.
    public func lock(timeout: TimeInterval) -> Int32? {
        try? FileManager.default.createDirectory(at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(lockURL.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            guard Date() < deadline else {
                close(fd)
                return nil
            }
            usleep(50_000)
        }
        return fd
    }

    // MARK: App side

    /// Answers requests on the main run loop with `handle`. Keep the port; invalidate it when quitting.
    @MainActor
    public func serve(_ handle: @escaping @MainActor ([String]) -> CLI.Output) -> CFMessagePort? {
        // ponytail: the handler box is never released; the app serves until it exits.
        let box = Unmanaged.passRetained(Handler(handle)).toOpaque()
        var context = CFMessagePortContext(version: 0, info: box, retain: nil, release: nil, copyDescription: nil)
        guard let port = CFMessagePortCreateLocal(nil, portName as CFString, { _, _, request, info in
            let handler = Unmanaged<Handler>.fromOpaque(info!).takeUnretainedValue()
            let output: CLI.Output
            if let request, let args = try? JSONDecoder().decode([String].self, from: request as Data) {
                output = MainActor.assumeIsolated { handler.handle(args) }
            } else {
                output = CLI.Output(err: "metodo: MeToDo couldn't read the request.\n", status: 1)
            }
            return (try? JSONEncoder().encode(output)).map { Unmanaged.passRetained($0 as CFData) }
        }, &context, nil) else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMessagePortCreateRunLoopSource(nil, port, 0), .commonModes)
        return port
    }

    private final class Handler {
        let handle: @MainActor ([String]) -> CLI.Output
        init(_ handle: @escaping @MainActor ([String]) -> CLI.Output) { self.handle = handle }
    }

    // MARK: CLI side

    /// Runs `args` in the app. nil when no app is serving this data file.
    public func send(_ args: [String], timeout: TimeInterval = 30) -> CLI.Output? {
        guard let port = CFMessagePortCreateRemote(nil, portName as CFString) else { return nil }
        defer { CFMessagePortInvalidate(port) }
        guard let request = try? JSONEncoder().encode(args) else { return nil }
        var reply: Unmanaged<CFData>?
        let status = CFMessagePortSendRequest(port, 0, request as CFData, timeout, timeout,
                                              CFRunLoopMode.defaultMode.rawValue, &reply)
        if status == kCFMessagePortSuccess, let data = reply?.takeRetainedValue() as Data?,
           let output = try? JSONDecoder().decode(CLI.Output.self, from: data) {
            return output
        }
        if status == kCFMessagePortIsInvalid { return nil }   // the app quit before taking the request
        // Sent but unanswered: it may still be applied, so retrying could do it twice.
        return CLI.Output(err: "metodo: MeToDo didn't answer (error \(status)). Check with `metodo list` before retrying.\n", status: 1)
    }
}
