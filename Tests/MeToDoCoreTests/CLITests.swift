import Testing
import Foundation
@testable import MeToDoCore

@MainActor
@Suite struct CLITests {
    let now = iso("2026-10-06T10:00:00Z")

    func makeStore() -> Store {
        let fixed = now
        let store = Store(persistence: nil, now: { fixed }, calendar: utc)
        store.addProject(name: "Work", color: .green, emoji: "💼")
        store.addProject(name: "Home", color: .blue, emoji: nil)
        return store
    }

    @discardableResult
    func run(_ store: Store, _ args: String...) -> CLI.Output {
        CLI.run(args, store: store, now: now, calendar: utc)
    }

    /// Runs with --json and returns the decoded object (or array).
    func json(_ store: Store, _ args: String...) throws -> Any {
        let o = CLI.run(args + ["--json"], store: store, now: now, calendar: utc)
        #expect(o.status == 0, "\(o.err)")
        return try JSONSerialization.jsonObject(with: Data(o.out.utf8))
    }

    func id(_ obj: Any) throws -> String { try #require((obj as? [String: Any])?["id"] as? String) }

    @Test func helpNeedsNoData() {
        #expect(CLI.help(for: [])?.out == CLI.usage)
        #expect(CLI.help(for: ["add", "--help"]) != nil)
        #expect(CLI.help(for: ["list"]) == nil)
    }

    @Test func addWithProjectDueAndNotes() throws {
        let store = makeStore()
        let t = try #require(json(store, "add", "Call", "Ana", "--project", "wor", "--due", "2026-10-07 14:30", "--notes", "re: budget")
            as? [String: Any])
        #expect(t["title"] as? String == "Call Ana")
        #expect(t["project"] as? String == "Work")
        #expect(t["notes"] as? String == "re: budget")
        #expect(t["due"] as? String == "2026-10-07T14:30:00Z")
        #expect(store.data.tasks.count == 1)
    }

    @Test func titleIsLiteralUnlessParse() throws {
        let store = makeStore()
        run(store, "add", "Email Bob about the March budget #home")
        #expect(store.data.tasks[0].title == "Email Bob about the March budget #home")
        #expect(store.data.tasks[0].remindAt == nil)
        run(store, "add", "--parse", "Mop floors #home")
        #expect(store.data.tasks[1].title == "Mop floors")
        #expect(store.project(store.data.tasks[1].projectID)?.name == "Home")
    }

    @Test func badInputChangesNothing() {
        let store = makeStore()
        for args in [["add", "x", "--project", "nope"], ["add", "x", "--due", "someday maybe"], ["add", "x", "--bogus", "1"],
                     ["add", "   "], ["frobnicate"], ["list", "weird"]] {
            let o = CLI.run(args, store: store, now: now, calendar: utc)
            #expect(o.status == 1, "\(args)")
            #expect(o.err.hasPrefix("metodo: "))
        }
        #expect(store.data.tasks.isEmpty)
    }

    @Test func idsArePrefixesAndMustBeUniqueAndLongEnough() throws {
        let store = makeStore()
        let a = try #require(store.addTask("A"))
        store.addTask("B")
        #expect(run(store, "complete", String(a.id.uuidString.prefix(3))).err.contains("too short"))
        #expect(run(store, "complete", "0000-nope").err.contains("no task"))
        #expect(run(store, "complete", String(a.id.uuidString.prefix(6)).lowercased()).status == 0)
        #expect(store.task(a.id)?.isDone == true)
    }

    @Test func oneBadIdInAListChangesNothing() throws {
        let store = makeStore()
        let a = try #require(store.addTask("A"))
        #expect(run(store, "complete", a.id.uuidString, "ffffffff").status == 1)
        #expect(store.task(a.id)?.isDone == false)
    }

    @Test func completeReopenAndReopenFromHistory() throws {
        let store = makeStore()
        let a = try #require(store.addTask("A"))
        let b = try #require(store.addTask("B"))
        run(store, "complete", a.id.uuidString, b.id.uuidString)
        #expect(store.data.tasks.allSatisfy { $0.isDone })
        store.clearDone([b.id])
        let done = try #require(json(store, "list", "completed") as? [[String: Any]])
        #expect(done.map { $0["title"] as? String } == ["A", "B"] || done.map { $0["title"] as? String } == ["B", "A"])
        #expect(done.first { $0["title"] as? String == "B" }?["cleared"] as? Bool == true)
        run(store, "reopen", a.id.uuidString, b.id.uuidString)
        #expect(store.data.tasks.count == 2)
        #expect(store.data.tasks.allSatisfy { !$0.isDone })
        #expect(store.data.archive.isEmpty)
    }

    @Test func editChangesOnlyWhatsGiven() throws {
        let store = makeStore()
        let t = try #require(store.addTask("Old", remindAt: iso("2026-10-07T09:00:00Z"), notes: "keep"))
        let ref = String(t.id.uuidString.prefix(8))
        #expect(run(store, "edit", ref).err.contains("nothing to change"))
        run(store, "edit", ref, "--title", "New", "--project", "home")
        var got = try #require(store.task(t.id))
        #expect(got.title == "New")
        #expect(got.notes == "keep")
        #expect(got.remindAt == iso("2026-10-07T09:00:00Z"))
        #expect(store.project(got.projectID)?.name == "Home")
        run(store, "edit", ref, "--due", "none", "--notes", "")
        got = try #require(store.task(t.id))
        #expect(got.remindAt == nil)
        #expect(got.notes.isEmpty)
    }

    @Test func changesFromTheCLIAreUndoable() throws {
        let store = makeStore()
        let t = try #require(store.addTask("T"))
        let undo = UndoManager()
        undo.groupsByEvent = false
        store.undoManager = undo
        undo.beginUndoGrouping()
        run(store, "edit", t.id.uuidString, "--notes", "from cli")
        undo.endUndoGrouping()
        #expect(store.task(t.id)?.notes == "from cli")
        undo.undo()
        #expect(store.task(t.id)?.notes == "")
    }

    @Test func deleteRemovesTasks() throws {
        let store = makeStore()
        let t = try #require(store.addTask("Gone"))
        let o = run(store, "delete", t.id.uuidString)
        #expect(o.out.contains("Deleted:"))
        #expect(store.data.tasks.isEmpty)
    }

    @Test func subtasksByNumberOrId() throws {
        let store = makeStore()
        let t = try #require(store.addTask("Trip"))
        let ref = t.id.uuidString
        run(store, "subtask", "add", ref, "Pack", "bags")
        run(store, "subtask", "add", ref, "Book hotel")
        #expect(store.task(t.id)?.subtasks.map(\.title) == ["Pack bags", "Book hotel"])
        run(store, "subtask", "complete", ref, "2")
        run(store, "subtask", "complete", ref, "2")   // idempotent
        #expect(store.task(t.id)?.subtasks.map(\.isDone) == [false, true])
        let sub = try #require(store.task(t.id)?.subtasks[1])
        run(store, "subtask", "reopen", ref, String(sub.id.uuidString.prefix(8)))
        #expect(store.task(t.id)?.subtasks.map(\.isDone) == [false, false])
        #expect(run(store, "subtask", "complete", ref, "7").status == 1)
    }

    @Test func listFilters() throws {
        let store = makeStore()
        let work = try #require(store.data.projects.first { $0.name == "Work" })
        store.addTask("Due today", remindAt: iso("2026-10-06T15:00:00Z"))
        store.addTask("Later", projectID: work.id, remindAt: iso("2026-10-20T09:00:00Z"))
        store.addTask("Pulled in", projectID: work.id, inToday: true)
        func titles(_ args: String...) throws -> [String] {
            let o = CLI.run(args + ["--json"], store: store, now: now, calendar: utc)
            return try #require(try JSONSerialization.jsonObject(with: Data(o.out.utf8)) as? [[String: Any]]).compactMap { $0["title"] as? String }
        }
        #expect(try titles("list") == ["Due today", "Later", "Pulled in"])
        #expect(try titles("list", "today") == ["Due today", "Pulled in"])
        #expect(try titles("list", "--project", "work") == ["Later", "Pulled in"])
        #expect(try titles("list", "today", "--project", "work") == ["Pulled in"])
        #expect(run(store, "list").out.contains("○ Due today"))
        let projects = try #require(json(store, "projects") as? [[String: Any]])
        #expect(projects.map { $0["openTasks"] as? Int } == [1, 2, 0])
    }

    // MARK: URLs

    @Test func urlsBecomeArguments() {
        #expect(CLI.arguments(from: URL(string: "metodo://add?title=Buy%20milk&project=work&due=tomorrow+9am&today=1")!)
            == ["add", "--title", "Buy milk", "--project", "work", "--due", "tomorrow 9am", "--today"])
        #expect(CLI.arguments(from: URL(string: "metodo://subtask/complete?id=3f2a&subtask=1")!)
            == ["subtask", "complete", "--id", "3f2a", "--subtask", "1"])
        #expect(CLI.arguments(from: URL(string: "metodo://add?title=1%2B1")!) == ["add", "--title", "1+1"])
        #expect(CLI.arguments(from: URL(string: "https://add?title=x")!) == nil)
    }

    @Test func urlsAddAndCompleteButNeverDelete() throws {
        let store = makeStore()
        #expect(CLI.run(url: URL(string: "metodo://add?title=From%20a%20link&project=home")!, store: store).status == 0)
        let t = try #require(store.data.tasks.first)
        #expect(t.title == "From a link")
        #expect(CLI.run(url: URL(string: "metodo://delete?id=\(t.id.uuidString)")!, store: store).status == 1)
        #expect(CLI.run(url: URL(string: "metodo://complete?id=\(t.id.uuidString)")!, store: store).status == 0)
        #expect(store.task(t.id)?.isDone == true)
    }

    // MARK: Files and the app link

    @Test func runOnFileSavesAndKeepsIdsStable() throws {
        let url = tempURL()
        let p = Persistence(url: url)
        let first = CLI.run(["projects", "--json"], persistence: p)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(CLI.run(["projects", "--json"], persistence: p).out == first.out)
        #expect(CLI.run(["add", "Saved"], persistence: p).status == 0)
        guard case .loaded(let data) = p.load() else { Issue.record("not saved"); return }
        #expect(data.tasks.map(\.title) == ["Saved"])
    }

    @Test func runOnFileLeavesAnUnreadableFileAlone() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: url)
        let o = CLI.run(["add", "x"], persistence: Persistence(url: url))
        #expect(o.status == 1)
        #expect(try String(contentsOf: url, encoding: .utf8) == "{ not json")
    }

    @Test func lockIsExclusiveUntilClosed() throws {
        let link = AppLink(persistence: Persistence(url: tempURL()))
        let held = try #require(link.lock(timeout: 0))
        #expect(link.lock(timeout: 0.1) == nil)
        close(held)
        let again = try #require(link.lock(timeout: 0))
        close(again)
    }

    @Test func eachDataFileHasItsOwnPort() {
        let a = AppLink(persistence: Persistence(url: URL(fileURLWithPath: "/tmp/a/data.json")))
        let b = AppLink(persistence: Persistence(url: URL(fileURLWithPath: "/tmp/b/data.json")))
        #expect(a.portName != b.portName)
        #expect(a.portName == AppLink(persistence: Persistence(url: URL(fileURLWithPath: "/tmp/a/../a/data.json"))).portName)
        #expect(AppLink(persistence: Persistence(url: URL(fileURLWithPath: "/x"))).send(["list"]) == nil)
    }
}

@Suite struct DuePhraseTests {
    @Test func isoAndPlainDates() {
        #expect(QuickAdd.date(from: "2026-10-07T14:30:00Z", calendar: utc) == iso("2026-10-07T14:30:00Z"))
        #expect(QuickAdd.date(from: "2026-10-07 14:30", calendar: utc) == iso("2026-10-07T14:30:00Z"))
        #expect(QuickAdd.date(from: "2026-10-07", calendar: utc) == iso("2026-10-07T09:00:00Z"))
    }

    @Test func phrasesLikeTheAddField() throws {
        let d = try #require(QuickAdd.date(from: "tomorrow 9am"))
        #expect(d == Queries.at(hour: 9, daysFromNow: 1, now: Date()))
        #expect(QuickAdd.date(from: "on friday") != nil)
        let soon = try #require(QuickAdd.date(from: "in 2 hours"))
        #expect(abs(soon.timeIntervalSinceNow - 7200) < 120)
    }

    @Test(arguments: ["", "someday", "tomorrow and also stuff", "42"])
    func anythingElseIsRejected(_ phrase: String) {
        #expect(QuickAdd.date(from: phrase) == nil)
    }
}
