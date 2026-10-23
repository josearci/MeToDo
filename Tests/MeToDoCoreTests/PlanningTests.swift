import Testing
import Foundation
@testable import MeToDoCore

/// Priority, estimates, subtask due dates and Today planning.
@Suite struct PlanningModelTests {
    let now = iso("2026-10-06T10:00:00Z")
    let p = UUID()

    @Test func oldFilesLoadWithDefaults() throws {
        let json = """
        {"projects":[{"id":"6B1E1D3C-1111-4F00-9A00-000000000001","name":"Inbox","color":"gray","isInbox":true}],
         "tasks":[{"id":"6B1E1D3C-1111-4F00-9A00-000000000002","projectID":"6B1E1D3C-1111-4F00-9A00-000000000001",
                   "title":"Old","subtasks":[{"id":"6B1E1D3C-1111-4F00-9A00-000000000003","title":"s","isDone":false}]}]}
        """
        let d = try JSONDecoder.metodo.decode(AppData.self, from: Data(json.utf8))
        #expect(d.tasks[0].priority == .none)
        #expect(d.tasks[0].estimate == nil)
        #expect(d.tasks[0].subtasks[0].dueAt == nil)
        #expect(d.tasks[0].subtasks[0].estimate == nil)
    }

    @Test func unknownPriorityReadsAsNoneInsteadOfFailingTheFile() throws {
        let json = #"{"id":"6B1E1D3C-1111-4F00-9A00-000000000002","projectID":"6B1E1D3C-1111-4F00-9A00-000000000001","title":"x","priority":"critical"}"#
        #expect(try JSONDecoder.metodo.decode(TaskItem.self, from: Data(json.utf8)).priority == .none)
    }

    @Test func newFieldsRoundTrip() throws {
        let t = TaskItem(projectID: p, title: "Report", subtasks: [Subtask(title: "Draft", dueAt: now, estimate: 45)],
                         priority: .high, estimate: 120)
        #expect(try JSONDecoder.metodo.decode(TaskItem.self, from: JSONEncoder.metodo.encode(t)) == t)
    }

    @Test(arguments: [("high", Priority.high), ("H", .high), ("med", .medium), ("urgent", .urgent), ("P1", .urgent),
                      ("p4", .low), ("none", Priority.none), ("n", Priority.none)])
    func priorityParsing(_ s: String, _ expected: Priority) {
        #expect(Priority(parsing: s) == expected)
    }

    @Test func badPrioritiesAreRejectedAndOrderIsLowToUrgent() {
        #expect(Priority(parsing: "") == nil)
        #expect(Priority(parsing: "p5") == nil)
        #expect(Priority(parsing: "critical") == nil)
        #expect(Priority.allCases.sorted() == [.none, .low, .medium, .high, .urgent])
    }

    @Test(arguments: [("90", 90), ("90m", 90), ("45 min", 45), ("2h", 120), ("1.5h", 90), ("1h30m", 90), ("1h 30m", 90),
                      ("1:30", 90), ("2 hours", 120)])
    func durations(_ s: String, _ minutes: Int) {
        #expect(QuickAdd.minutes(from: s) == minutes)
    }

    @Test(arguments: ["", "soon", "h", "1h30", "-5m"])
    func badDurations(_ s: String) {
        #expect(QuickAdd.minutes(from: s) == nil)
    }

    @Test func durationLabels() {
        #expect(Queries.durationLabel(45) == "45m")
        #expect(Queries.durationLabel(90) == "1h 30m")
        #expect(Queries.durationLabel(120) == "2h")
        #expect(Queries.durationLabel(0) == "0m")
    }
}

@Suite struct PlanningQueryTests {
    let now = iso("2026-10-06T10:00:00Z")
    let work = Project(name: "Work", color: .green)

    func data(_ tasks: [TaskItem]) -> AppData {
        var d = AppData.fresh()
        d.projects.append(work)
        d.tasks = tasks
        return d
    }

    @Test func openSubtaskDueTodayPullsTaskIntoToday() {
        let today = TaskItem(projectID: work.id, title: "due sub", remindAt: iso("2026-10-20T09:00:00Z"),
                             subtasks: [Subtask(title: "piece", dueAt: iso("2026-10-06T15:00:00Z"))])
        let doneSub = TaskItem(projectID: work.id, title: "done sub",
                               subtasks: [Subtask(title: "piece", isDone: true, dueAt: iso("2026-10-06T15:00:00Z"))])
        let later = TaskItem(projectID: work.id, title: "later sub", subtasks: [Subtask(title: "piece", dueAt: iso("2026-10-07T09:00:00Z"))])
        #expect(Queries.isInToday(today, now: now, calendar: utc))
        #expect(!Queries.isInToday(doneSub, now: now, calendar: utc))
        #expect(!Queries.isInToday(later, now: now, calendar: utc))
    }

    @Test func todayIsPriorityThenDueThenManualOrder() {
        let tasks = [
            TaskItem(projectID: work.id, title: "pinned none", inToday: true),
            TaskItem(projectID: work.id, title: "pinned high", inToday: true, priority: .high),
            TaskItem(projectID: work.id, title: "15:00 none", remindAt: iso("2026-10-06T15:00:00Z")),
            TaskItem(projectID: work.id, title: "overdue none", remindAt: iso("2026-10-05T09:00:00Z")),
            TaskItem(projectID: work.id, title: "sub 12:00 high", subtasks: [Subtask(title: "s", dueAt: iso("2026-10-06T12:00:00Z"))],
                     priority: .high),
            TaskItem(projectID: work.id, title: "pinned urgent", inToday: true, priority: .urgent),
            TaskItem(projectID: work.id, title: "pinned low", inToday: true, priority: .low),
        ]
        #expect(Queries.today(data(tasks), now: now, calendar: utc).map(\.title) == [
            "pinned urgent", "sub 12:00 high", "pinned high", "pinned low", "overdue none", "15:00 none", "pinned none",
        ])
    }

    @Test func minutesLeftPrefersSubtaskBreakdown() {
        let plain = TaskItem(projectID: work.id, title: "plain", estimate: 60)
        #expect(Queries.minutesLeft(plain) == 60)
        #expect(Queries.minutesLeft(TaskItem(projectID: work.id, title: "none")) == nil)
        let split = TaskItem(projectID: work.id, title: "split", subtasks: [
            Subtask(title: "done", isDone: true, estimate: 30),
            Subtask(title: "today", dueAt: iso("2026-10-06T15:00:00Z"), estimate: 45),
            Subtask(title: "undated", estimate: 15),
            Subtask(title: "tomorrow", dueAt: iso("2026-10-07T09:00:00Z"), estimate: 120),
            Subtask(title: "unestimated"),
        ], estimate: 600)
        #expect(Queries.minutesLeft(split) == 180)
        #expect(Queries.minutesLeft(split, until: iso("2026-10-07T00:00:00Z")) == 60)
    }

    @Test func plannedAddsUpTodaysOpenTasks() {
        let d = data([
            TaskItem(projectID: work.id, title: "a", inToday: true, estimate: 90),
            TaskItem(projectID: work.id, title: "b", remindAt: iso("2026-10-06T15:00:00Z"), estimate: 60),
            TaskItem(projectID: work.id, title: "c", inToday: true, subtasks: [
                Subtask(title: "now", estimate: 30), Subtask(title: "later", dueAt: iso("2026-10-08T09:00:00Z"), estimate: 240),
            ]),
            TaskItem(projectID: work.id, title: "not today", estimate: 500),
            TaskItem(projectID: work.id, title: "done", isDone: true, inToday: true, estimate: 500),
        ])
        #expect(Queries.planned(Queries.today(d, now: now, calendar: utc), now: now, calendar: utc) == 180)
    }
}

@MainActor
@Suite struct PlanningCLITests {
    let now = iso("2026-10-06T10:00:00Z")

    func makeStore() -> Store {
        let fixed = now
        let store = Store(persistence: nil, now: { fixed }, calendar: utc)
        store.addProject(name: "Work", color: .green, emoji: "💼")
        return store
    }

    @discardableResult
    func run(_ store: Store, _ args: String...) -> CLI.Output { CLI.run(args, store: store, now: now, calendar: utc) }

    func json(_ store: Store, _ args: String...) throws -> Any {
        let o = CLI.run(args + ["--json"], store: store, now: now, calendar: utc)
        #expect(o.status == 0, "\(o.err)")
        return try JSONSerialization.jsonObject(with: Data(o.out.utf8))
    }

    @Test func addAndEditPriorityAndEstimate() throws {
        let store = makeStore()
        let t = try #require(json(store, "add", "Write report", "--priority", "high", "--estimate", "1h30m") as? [String: Any])
        #expect(t["priority"] as? String == "high")
        #expect(t["estimate"] as? Int == 90)
        let id = try #require(t["id"] as? String)
        run(store, "edit", id, "--priority", "p1", "--estimate", "2h")
        #expect(store.data.tasks[0].priority == .urgent)
        #expect(store.data.tasks[0].estimate == 120)
        #expect(run(store, "list").out.contains("urgent · ~2h"))
        run(store, "edit", id, "--priority", "none", "--estimate", "none")
        #expect(store.data.tasks[0].priority == .none)
        #expect(store.data.tasks[0].estimate == nil)
    }

    @Test func badPriorityOrEstimateChangesNothing() {
        let store = makeStore()
        for args in [["add", "x", "--priority", "critical"], ["add", "x", "--estimate", "soon"], ["add", "x", "--estimate", "0"]] {
            let o = CLI.run(args, store: store, now: now, calendar: utc)
            #expect(o.status == 1)
            #expect(!o.err.isEmpty)
        }
        #expect(store.data.tasks.isEmpty)
    }

    @Test func subtaskDueTodayBringsTaskIntoTodayWithFullJSON() throws {
        let store = makeStore()
        let t = try #require(store.addTask("Big project", estimate: 600))
        #expect(Queries.today(store.data, now: now, calendar: utc).isEmpty)
        run(store, "subtask", "add", String(t.id.uuidString.prefix(8)), "Outline", "--due", "2026-10-06 15:00", "--estimate", "45m")
        run(store, "subtask", "add", t.id.uuidString, "Draft", "--due", "2026-10-08", "--estimate", "3h")
        let list = try #require(json(store, "list", "today") as? [[String: Any]])
        #expect(list.count == 1)
        let task = list[0]
        #expect(task["id"] as? String == t.id.uuidString)
        #expect(task["priority"] as? String == "none")
        #expect(task["estimate"] as? Int == 600)
        #expect(task["minutesLeft"] as? Int == 225)
        #expect(task["today"] as? Bool == true)
        let subs = try #require(task["subtasks"] as? [[String: Any]])
        #expect(subs.map { $0["due"] as? String } == ["2026-10-06T15:00:00Z", "2026-10-08T09:00:00Z"])
        #expect(subs.map { $0["estimate"] as? Int } == [45, 180])
        #expect(subs.map { $0["done"] as? Bool } == [false, false])
        #expect(subs.allSatisfy { $0["id"] is String })
        // Only today's piece counts toward the plan.
        #expect(run(store, "today").out.hasSuffix("45m planned\n"))
    }

    @Test func subtaskEditChangesDueAndEstimate() throws {
        let store = makeStore()
        let t = try #require(store.addTask("Big"))
        store.addSubtask(t.id, title: "Piece", estimate: 30)
        let id = t.id.uuidString
        run(store, "subtask", "edit", id, "1", "--due", "2026-10-06 16:00", "--estimate", "1h")
        #expect(store.data.tasks[0].subtasks[0].dueAt == iso("2026-10-06T16:00:00Z"))
        #expect(store.data.tasks[0].subtasks[0].estimate == 60)
        run(store, "subtask", "edit", id, "1", "--due", "none", "--estimate", "none", "--title", "Renamed")
        #expect(store.data.tasks[0].subtasks[0] == Subtask(id: store.data.tasks[0].subtasks[0].id, title: "Renamed"))
        #expect(run(store, "subtask", "edit", id, "1").status == 1)
    }

    @Test func subtaskNumberOnTaskWithoutSubtasksIsAnErrorNotACrash() throws {
        let store = makeStore()
        let t = try #require(store.addTask("Empty"))
        #expect(run(store, "subtask", "complete", t.id.uuidString, "1").status == 1)
    }

    @Test func todayAddAndRemove() throws {
        let store = makeStore()
        let a = try #require(store.addTask("Pick me"))
        let b = try #require(store.addTask("Due today", remindAt: iso("2026-10-06T17:00:00Z")))
        run(store, "today", "add", a.id.uuidString, b.id.uuidString)
        #expect(store.task(a.id)?.inToday == true)
        run(store, "today", "add", a.id.uuidString)   // idempotent
        #expect(store.task(a.id)?.inToday == true)
        let removed = run(store, "today", "remove", a.id.uuidString, b.id.uuidString)
        #expect(store.task(a.id)?.inToday == false)
        #expect(removed.out.contains("still in Today"))   // b is due today
        #expect(Queries.today(store.data, now: now, calendar: utc).map(\.id) == [b.id])
        #expect(run(store, "today", "bogus").status == 1)
        run(store, "edit", a.id.uuidString, "--today")
        #expect(store.task(a.id)?.inToday == true)
    }

    @Test func urlSchemeCarriesPriorityAndEstimate() throws {
        let store = makeStore()
        let o = CLI.run(url: URL(string: "metodo://add?title=Plan&priority=urgent&estimate=30m&today=1")!, store: store)
        #expect(o.status == 0, "\(o.err)")
        let t = try #require(store.data.tasks.first)
        #expect((t.priority, t.estimate, t.inToday) == (.urgent, 30, true))
        #expect(CLI.run(url: URL(string: "metodo://today/remove?id=\(t.id.uuidString)")!, store: store).status == 0)
        #expect(store.task(t.id)?.inToday == false)
    }
}

@MainActor
@Suite struct PlanningStoreTests {
    @Test func setTodayAndEstimates() throws {
        let store = Store(persistence: nil)
        let t = try #require(store.addTask("t"))
        store.setToday(t.id, true)
        store.setToday(t.id, true)
        #expect(store.task(t.id)?.inToday == true)
        store.setEstimate(t.id, 0)
        #expect(store.task(t.id)?.estimate == nil)
        let s = try #require(store.addSubtask(t.id, title: "s", estimate: 0))
        #expect(s.estimate == nil)
        store.setSubtaskEstimate(t.id, s.id, 20)
        #expect(store.task(t.id)?.subtasks[0].estimate == 20)
        store.complete(t.id)
        store.setToday(t.id, true)
        #expect(store.task(t.id)?.inToday == false)   // done tasks never get ☀️
    }
}
