import Foundation

/// The `metodo` command line, run against a Store. The `metodo` binary runs it on a Store over data.json
/// when MeToDo isn't running; when it is, the app runs it on its own Store (see AppLink). metodo:// URLs
/// are translated into the same arguments.
@MainActor
public enum CLI {
    public struct Output: Codable, Equatable, Sendable {
        public var out = ""
        public var err = ""
        public var status: Int32 = 0

        public init(out: String = "", err: String = "", status: Int32 = 0) {
            self.out = out
            self.err = err
            self.status = status
        }
    }

    struct Failure: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }

    nonisolated public static let usage = """
    metodo — manage MeToDo tasks from the terminal.

    USAGE
      metodo <command> [arguments] [options]

    COMMANDS
      list [all|today|completed]       Open tasks (default: all), Today, or every finished task
           [--project NAME]            Only this project
      projects                         Projects and their open task counts
      show <id>                        One task with its notes and subtasks
      add <title…>                     Add a task (to the Inbox unless --project)
           [--project NAME] [--due WHEN] [--notes TEXT] [--today]
           [--parse]                   Read #project and a date from the title, like the app's Add field
      complete <id…>                   Mark tasks done
      reopen <id…>                     Untick done tasks, or bring cleared ones back
      edit <id> [--title T] [--notes N] [--due WHEN|none] [--project NAME]
      delete <id…>                     Delete tasks (⌘Z in the app undoes it)
      subtask add <task-id> <title…>   Add a subtask
      subtask complete <task-id> <n|subtask-id>
      subtask reopen <task-id> <n|subtask-id>

    OPTIONS
      --json        Machine-readable output with full ids (lists, show, and every change)
      -h, --help    This help

    IDS
      Any unique prefix of a task id works (at least 4 characters); lists show the first 8.
      Subtasks are referred to by their number in `metodo show` or by id prefix.

    WHEN (--due)
      Anything the Add field understands — "tomorrow 9am", "friday", "next monday 3pm",
      "in 2 hours" — or "2026-10-23", "2026-10-23 14:30", full ISO 8601. A day without a time means 9:00.

    PROJECTS (--project)
      Name without emoji, case and accents don't matter, a unique prefix works: --project work

    DATA
      Works whether or not MeToDo is running: a running app applies the change itself, so its
      window updates at once and nothing is overwritten. METODO_DATA=/path/data.json points the
      CLI at another data file.

    EXAMPLES
      metodo add "Call Ana" --project work --due "tomorrow 9am"
      metodo add --parse "Pay rent #home friday"
      metodo list today --json
      metodo complete 3f2a1b9c
      metodo edit 3f2a --due none --notes "Waiting on Bob"
      metodo subtask add 3f2a "Buy stamps" && metodo subtask complete 3f2a 1

    """

    // MARK: Entry points

    /// `metodo --help`, `metodo help`, `metodo` with nothing: answered without touching any data.
    nonisolated public static func help(for arguments: [String]) -> Output? {
        guard arguments.isEmpty || arguments.first == "help" || arguments.contains("--help") || arguments.contains("-h")
        else { return nil }
        return Output(out: usage)
    }

    public static func run(_ arguments: [String], store: Store, now: Date = Date(), calendar: Calendar = .current) -> Output {
        if let help = help(for: arguments) { return help }
        var runner = Runner(store: store, now: now, calendar: calendar)
        do {
            try runner.run(arguments)
            return Output(out: runner.out)
        } catch let f as Failure {
            return Output(out: runner.out, err: "metodo: \(f.message)\n", status: 1)
        } catch {
            return Output(out: runner.out, err: "metodo: \(error.localizedDescription)\n", status: 1)
        }
    }

    /// Runs against data.json directly. Only call this while holding AppLink's lock (MeToDo isn't running).
    public static func run(_ arguments: [String], persistence: Persistence) -> Output {
        if let help = help(for: arguments) { return help }
        let url = persistence.url
        let exists = FileManager.default.fileExists(atPath: url.path)
        if exists, (try? JSONDecoder.metodo.decode(AppData.self, from: Data(contentsOf: url))) == nil {
            // Store would move it aside and start empty; leave that (and its alert) to the app.
            return Output(err: "metodo: \(url.path) can't be read. Open MeToDo to recover it; nothing was changed.\n", status: 1)
        }
        let store = Store(persistence: persistence)
        let before = store.data
        var output = run(arguments, store: store)
        if store.data != before || !exists {   // a new file: save it so the Inbox id stays the same
            store.saveNow()
            if let e = store.saveError {
                output.err += "metodo: \(e)\n"
                output.status = 1
            }
        }
        return output
    }

    /// metodo://add?title=Buy%20milk&project=work&due=tomorrow%209am → ["add", "--title", "Buy milk", …].
    /// Path segments after the command become words: metodo://subtask/add?id=…&title=…
    /// Deleting isn't offered: any web page can open a URL.
    public static func run(url: URL, store: Store) -> Output {
        guard let args = arguments(from: url) else {
            return Output(err: "metodo: \(url.absoluteString) isn't a MeToDo command.\n", status: 1)
        }
        if args.first == "delete" {
            return Output(err: "metodo: deleting isn't available from a link; use the metodo command.\n", status: 1)
        }
        return run(args, store: store)
    }

    nonisolated public static func arguments(from url: URL) -> [String]? {
        guard url.scheme?.lowercased() == "metodo",
              let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let command = c.host?.lowercased(), !command.isEmpty else { return nil }
        var args = [command] + c.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        for item in c.percentEncodedQueryItems ?? [] {
            // Form-style "+" means a space; a literal plus arrives as %2B.
            let value = (item.value ?? "").replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? ""
            if booleanOptions.contains(item.name) {
                if ["", "1", "true", "yes"].contains(value.lowercased()) { args.append("--\(item.name)") }
            } else {
                args += ["--\(item.name)", value]
            }
        }
        return args
    }

    nonisolated static let booleanOptions: Set<String> = ["json", "today", "parse"]
}

// MARK: - Commands

@MainActor
private struct Runner {
    let store: Store
    let now: Date
    let calendar: Calendar
    var out = ""

    init(store: Store, now: Date, calendar: Calendar) {
        self.store = store
        self.now = now
        self.calendar = calendar
    }

    var data: AppData { store.data }

    mutating func run(_ arguments: [String]) throws {
        var rest = arguments
        let command = rest.removeFirst()
        if command == "subtask" {
            guard !rest.isEmpty else { throw CLI.Failure("subtask needs add, complete or reopen. See metodo --help.") }
            let action = rest.removeFirst()
            return try subtask(action, Args(rest))
        }
        let a = try Args(rest)
        switch command {
        case "list", "ls": try list(a)
        case "projects": try projects(a)
        case "show": try show(a)
        case "add": try add(a)
        case "complete", "done": try complete(a)
        case "reopen": try reopen(a)
        case "edit": try edit(a)
        case "delete", "rm": try delete(a)
        default: throw CLI.Failure("unknown command '\(command)'. See metodo --help.")
        }
    }

    // MARK: Reading

    mutating func list(_ a: Args) throws {
        try a.allow("project", "json")
        guard a.positional.count <= 1 else { throw CLI.Failure("list takes one of: all, today, completed.") }
        let project = try a.options["project"].map(findProject)
        let view = a.positional.first ?? "all"
        switch view {
        case "all", "today":
            var tasks = view == "all" ? Queries.open(data) : Queries.today(data, now: now, calendar: calendar)
            if let project { tasks = tasks.filter { $0.projectID == project.id } }
            if a.json { return emit(tasks.map(json)) }
            out += tasks.isEmpty ? "No tasks.\n" : tasks.map { line($0) + "\n" }.joined()
        case "completed", "done":
            var done = Queries.completed(data)
            if let project { done = done.filter { $0.projectID == project.id } }
            let listed = Set(data.tasks.map(\.id))
            if a.json { return emit(done.map { CompletedJSON($0, cleared: !listed.contains($0.id)) }) }
            out += done.isEmpty ? "Nothing completed yet.\n" : done.map { c in
                let name = [c.projectEmoji, c.projectName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
                let cleared = listed.contains(c.id) ? "" : " · cleared"
                return "\(short(c.id))  ✓ \(c.title)  (\(name) · done \(label(c.completedAt))\(cleared))\n"
            }.joined()
        default:
            throw CLI.Failure("unknown list '\(view)'; use all, today or completed.")
        }
    }

    mutating func projects(_ a: Args) throws {
        try a.allow("json")
        try a.noPositional()
        if a.json {
            return emit(data.projects.map {
                ProjectJSON(id: $0.id, name: $0.name, emoji: $0.emoji, isInbox: $0.isInbox,
                            openTasks: Queries.openCount(data, project: $0.id))
            })
        }
        for p in data.projects {
            out += "\(short(p.id))  \(p.displayName)  (\(Queries.openCount(data, project: p.id)) open)\n"
        }
    }

    mutating func show(_ a: Args) throws {
        try a.allow("id", "json")
        let t = try findTask(a.one("id", "a task id"))
        if a.json { return emit(json(t)) }
        out += "\(t.id.uuidString.lowercased())\n\(line(t))\n"
        if !t.notes.isEmpty {
            out += "Notes:\n" + t.notes.split(separator: "\n", omittingEmptySubsequences: false).map { "  \($0)\n" }.joined()
        }
        if !t.subtasks.isEmpty {
            out += "Subtasks:\n"
            for (i, s) in t.subtasks.enumerated() {
                out += "  \(i + 1). [\(s.isDone ? "x" : " ")] \(s.title)  (\(short(s.id)))\n"
            }
        }
    }

    // MARK: Changing

    mutating func add(_ a: Args) throws {
        try a.allow("title", "project", "due", "notes", "today", "parse", "json")
        var title = a.options["title"] ?? a.positional.joined(separator: " ")
        if a.options["title"] != nil && !a.positional.isEmpty { throw CLI.Failure("give the title once.") }
        var projectID = try a.options["project"].map(findProject)?.id
        var due = try a.options["due"].map(parseDue)
        if a.flags.contains("parse"), let r = QuickAdd.parse(title, projects: data.projects, calendar: calendar) {
            title = r.title
            projectID = projectID ?? r.projectID
            due = due ?? r.remindAt
        }
        guard let t = store.addTask(title, projectID: projectID, remindAt: due, inToday: a.flags.contains("today"),
                                    notes: a.options["notes"] ?? "") else {
            throw CLI.Failure("the task needs a title.")
        }
        report("Added", t, a)
    }

    mutating func complete(_ a: Args) throws {
        try a.allow("id", "json")
        let tasks = try a.ids().map(findTask)
        tasks.forEach { store.complete($0.id) }
        report("Completed", tasks.compactMap { store.task($0.id) }, a)
    }

    mutating func reopen(_ a: Args) throws {
        try a.allow("id", "json")
        // Done tasks still listed, then cleared ones from the archive.
        let listed = data.tasks.filter(\.isDone).map { Ref(id: $0.id, label: "\(short($0.id)) \($0.title)") }
        let cleared = data.archive.map { Ref(id: $0.id, label: "\(short($0.id)) \($0.title)") }
        let ids = try a.ids().map { try find($0, in: listed + cleared, what: "finished task").id }
        ids.forEach(store.reopen)
        report("Reopened", ids.compactMap(store.task), a)
    }

    mutating func edit(_ a: Args) throws {
        try a.allow("id", "title", "notes", "due", "project", "json")
        let t = try findTask(a.one("id", "a task id"))
        let project = try a.options["project"].map(findProject)
        let due = try a.options["due"].map { ["none", "clear", ""].contains($0.lowercased()) ? Date?.none : try parseDue($0) }
        guard a.options["title"] != nil || a.options["notes"] != nil || due != nil || project != nil else {
            throw CLI.Failure("nothing to change; give --title, --notes, --due or --project.")
        }
        if let title = a.options["title"] {
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CLI.Failure("the title can't be empty.") }
            store.rename(t.id, to: title)
        }
        if let notes = a.options["notes"] { store.setNotes(t.id, notes, undoable: true) }
        if let due { store.setReminder(t.id, due) }
        if let project { store.move(t.id, toProject: project.id) }
        report("Updated", try findTask(t.id.uuidString), a)
    }

    mutating func delete(_ a: Args) throws {
        try a.allow("id", "json")
        let tasks = try a.ids().map(findTask)
        let lines = tasks.map(line)
        tasks.forEach { store.delete($0.id) }
        if a.json { return emit(tasks.map(json)) }
        out += lines.map { "Deleted: \($0)\n" }.joined()
    }

    mutating func subtask(_ action: String, _ a: Args) throws {
        switch action {
        case "add":
            try a.allow("id", "title", "json")
            var words = a.positional
            guard let taskRef = a.options["id"] ?? (words.isEmpty ? nil : words.removeFirst()) else {
                throw CLI.Failure("subtask add needs a task id.")
            }
            let title = a.options["title"] ?? words.joined(separator: " ")
            let t = try findTask(taskRef)
            guard let s = store.addSubtask(t.id, title: title) else { throw CLI.Failure("the subtask needs a title.") }
            if a.json { return emit(json(try findTask(t.id.uuidString))) }
            out += "Added subtask \(t.subtasks.count + 1) (\(short(s.id))) to \(short(t.id)) \(t.title): \(s.title)\n"
        case "complete", "done", "reopen":
            try a.allow("id", "subtask", "json")
            var words = a.positional
            guard let taskRef = a.options["id"] ?? (words.isEmpty ? nil : words.removeFirst()),
                  let subRef = a.options["subtask"] ?? (words.isEmpty ? nil : words.removeFirst()) else {
                throw CLI.Failure("subtask \(action) needs a task id and a subtask number or id.")
            }
            guard words.isEmpty else { throw CLI.Failure("unexpected '\(words.joined(separator: " "))'.") }
            let t = try findTask(taskRef)
            let s: Subtask
            if let n = Int(subRef), (1...t.subtasks.count).contains(n) {
                s = t.subtasks[n - 1]
            } else {
                let refs = t.subtasks.map { Ref(id: $0.id, label: "\(short($0.id)) \($0.title)") }
                let id = try find(subRef, in: refs, what: "subtask").id
                s = t.subtasks.first { $0.id == id }!
            }
            if s.isDone == (action == "reopen") { store.toggleSubtask(t.id, s.id) }
            let updated = try findTask(t.id.uuidString)
            if a.json { return emit(json(updated)) }
            let p = updated.subtaskProgress
            out += "\(action == "reopen" ? "Reopened" : "Completed") subtask: \(s.title)  (\(p.done)/\(p.total) done in \(short(t.id)) \(t.title))\n"
        default:
            throw CLI.Failure("unknown subtask command '\(action)'; use add, complete or reopen.")
        }
    }

    // MARK: Lookups

    struct Ref {
        let id: UUID
        let label: String
    }

    func find(_ ref: String, in refs: [Ref], what: String) throws -> Ref {
        let r = ref.trimmingCharacters(in: .whitespaces).lowercased()
        guard r.count >= 4 else { throw CLI.Failure("'\(ref)' is too short; give at least 4 characters of the \(what) id.") }
        var seen = Set<UUID>()
        let hits = refs.filter { $0.id.uuidString.lowercased().hasPrefix(r) && seen.insert($0.id).inserted }
        switch hits.count {
        case 1: return hits[0]
        case 0: throw CLI.Failure("no \(what) with id '\(ref)'.")
        default: throw CLI.Failure("'\(ref)' matches \(hits.count) \(what)s (\(hits.map(\.label).joined(separator: ", "))); give more characters.")
        }
    }

    func findTask(_ ref: String) throws -> TaskItem {
        let refs = data.tasks.map { Ref(id: $0.id, label: "\(short($0.id)) \($0.title)") }
        let id = try find(ref, in: refs, what: "task").id
        return data.tasks.first { $0.id == id }!
    }

    func findProject(_ name: String) throws -> Project {
        if let p = QuickAdd.matchProject(name, in: data.projects) { return p }
        throw CLI.Failure("no project matches '\(name)'. Projects: \(data.projects.map(\.name).joined(separator: ", ")).")
    }

    func parseDue(_ phrase: String) throws -> Date {
        guard let d = QuickAdd.date(from: phrase, calendar: calendar) else {
            throw CLI.Failure("couldn't read '\(phrase)' as a date; try \"tomorrow 9am\", \"friday\" or \"2026-10-23 14:30\".")
        }
        return d
    }

    // MARK: Output

    func short(_ id: UUID) -> String { String(id.uuidString.prefix(8)).lowercased() }

    func label(_ date: Date) -> String { Queries.reminderLabel(date, now: now, calendar: calendar) }

    /// `3f2a1b9c  ○ Call Ana  (💼 Work · due Tomorrow 9:00 AM · 1/3 subtasks)`
    func line(_ t: TaskItem) -> String {
        var parts = [store.project(t.projectID)?.displayName ?? "?"]
        if t.isDone {
            parts.append("done" + (t.completedAt.map { " " + label($0) } ?? ""))
        } else if let r = t.remindAt {
            parts.append((Queries.isOverdue(t, now: now) ? "overdue since " : "due ") + label(r))
        }
        if t.inToday && !t.isDone { parts.append("☀️ today") }
        if !t.subtasks.isEmpty { parts.append("\(t.subtaskProgress.done)/\(t.subtaskProgress.total) subtasks") }
        if !t.notes.isEmpty { parts.append("notes") }
        return "\(short(t.id))  \(t.isDone ? "✓" : "○") \(t.title)  (\(parts.joined(separator: " · ")))"
    }

    func json(_ t: TaskItem) -> TaskJSON {
        TaskJSON(id: t.id, title: t.title, projectID: t.projectID, project: store.project(t.projectID)?.name ?? "",
                 done: t.isDone, completedAt: t.completedAt, due: t.remindAt, overdue: Queries.isOverdue(t, now: now),
                 inToday: t.inToday, today: Queries.isInToday(t, now: now, calendar: calendar), notes: t.notes,
                 subtasks: t.subtasks.map { SubtaskJSON(id: $0.id, title: $0.title, done: $0.isDone) },
                 createdAt: t.createdAt)
    }

    mutating func report(_ verb: String, _ t: TaskItem, _ a: Args) {
        if a.json { return emit(json(t)) }
        out += "\(verb): \(line(t))\n"
    }

    mutating func report(_ verb: String, _ tasks: [TaskItem], _ a: Args) {
        if a.json { return emit(tasks.map(json)) }
        out += tasks.map { "\(verb): \(line($0))\n" }.joined()
    }

    mutating func emit<T: Encodable>(_ value: T) {
        let e = JSONEncoder.metodo
        e.outputFormatting.insert(.withoutEscapingSlashes)
        out += String(decoding: (try? e.encode(value)) ?? Data(), as: UTF8.self) + "\n"
    }
}

// MARK: - Arguments

/// `--name value`, `--name=value`, boolean `--json`/`--today`/`--parse`, the rest positional; `--` ends options.
private struct Args {
    var positional: [String] = []
    var options: [String: String] = [:]
    var flags: Set<String> = []

    init(_ arguments: [String]) throws {
        var it = arguments.makeIterator()
        while let arg = it.next() {
            if arg == "--" {
                while let p = it.next() { positional.append(p) }
            } else if arg.hasPrefix("--") {
                var name = String(arg.dropFirst(2))
                var value: String?
                if let eq = name.firstIndex(of: "=") {
                    value = String(name[name.index(after: eq)...])
                    name = String(name[..<eq])
                }
                if CLI.booleanOptions.contains(name) {
                    flags.insert(name)
                } else {
                    guard let v = value ?? it.next() else { throw CLI.Failure("--\(name) needs a value.") }
                    options[name] = v
                }
            } else {
                positional.append(arg)
            }
        }
    }

    var json: Bool { flags.contains("json") }

    func allow(_ names: String...) throws {
        if let bad = (Array(options.keys) + flags).first(where: { !names.contains($0) }) {
            throw CLI.Failure("unknown option --\(bad) here. See metodo --help.")
        }
    }

    func noPositional() throws {
        guard positional.isEmpty else { throw CLI.Failure("unexpected '\(positional.joined(separator: " "))'.") }
    }

    /// Exactly one value, given positionally or as --name (URLs use the latter).
    func one(_ name: String, _ what: String) throws -> String {
        let all = positional + (options[name].map { [$0] } ?? [])
        guard all.count == 1 else { throw CLI.Failure(all.isEmpty ? "give \(what)." : "give only one \(what.replacingOccurrences(of: "a ", with: "")).") }
        return all[0]
    }

    func ids() throws -> [String] {
        let all = positional + (options["id"].map { [$0] } ?? [])
        guard !all.isEmpty else { throw CLI.Failure("give at least one task id.") }
        return all
    }
}

// MARK: - JSON shapes

private struct TaskJSON: Encodable {
    let id: UUID
    let title: String
    let projectID: UUID
    let project: String
    let done: Bool
    let completedAt: Date?
    let due: Date?
    let overdue: Bool
    /// Pulled into Today by hand (☀️).
    let inToday: Bool
    /// Shows in the Today view: pulled in, or due today or earlier.
    let today: Bool
    let notes: String
    let subtasks: [SubtaskJSON]
    let createdAt: Date?
}

private struct SubtaskJSON: Encodable {
    let id: UUID
    let title: String
    let done: Bool
}

private struct ProjectJSON: Encodable {
    let id: UUID
    let name: String
    let emoji: String?
    let isInbox: Bool
    let openTasks: Int
}

private struct CompletedJSON: Encodable {
    let id: UUID
    let title: String
    let projectID: UUID
    let project: String
    let completedAt: Date
    let due: Date?
    let notes: String?
    /// Cleared from the lists (only in the history now).
    let cleared: Bool

    init(_ c: CompletedTask, cleared: Bool) {
        id = c.id
        title = c.title
        projectID = c.projectID
        project = c.projectName
        completedAt = c.completedAt
        due = c.dueAt
        notes = c.notes
        self.cleared = cleared
    }
}
