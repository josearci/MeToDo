import AppKit
import MeToDoCore

// `metodo`: shipped inside MeToDo.app as Contents/Helpers/metodo (this target's binary can't be named
// "metodo" itself: it would collide with "MeToDo" on a case-insensitive disk). See CLI.usage.

let args = Array(CommandLine.arguments.dropFirst())

func finish(_ output: CLI.Output) -> Never {
    FileHandle.standardOutput.write(Data(output.out.utf8))
    FileHandle.standardError.write(Data(output.err.utf8))
    exit(output.status)
}

if let help = CLI.help(for: args) { finish(help) }

let link = AppLink(persistence: Persistence(url: Persistence.defaultURL))

// Lock free → MeToDo isn't running: work on the file, holding the lock so the app can't start
// and load it halfway. Lock taken → the app (or another metodo, briefly) has it: ask the app.
let deadline = Date().addingTimeInterval(10)
while true {
    if let fd = link.lock(timeout: 0) {
        // A MeToDo from before the CLI existed doesn't take the lock and would save over our change.
        if ProcessInfo.processInfo.environment["METODO_DATA"] == nil,
           !NSRunningApplication.runningApplications(withBundleIdentifier: "com.josearci.metodo").isEmpty {
            finish(CLI.Output(err: "metodo: the MeToDo that's running is an older version. Quit it and open it again, then retry; nothing was changed.\n", status: 1))
        }
        let output = MainActor.assumeIsolated { CLI.run(args, persistence: link.persistence) }
        close(fd)
        finish(output)
    }
    if let output = link.send(args) { finish(output) }
    if Date() > deadline {
        finish(CLI.Output(err: """
            metodo: MeToDo is running but can't be reached (e.g. from an SSH session), so nothing was changed.
            Quit MeToDo, or run metodo from a Terminal on this Mac's desktop.

            """, status: 1))
    }
    usleep(100_000)
}
