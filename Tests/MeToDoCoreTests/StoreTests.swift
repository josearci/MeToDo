import Testing
import Foundation
@testable import MeToDoCore

@MainActor
@Suite struct StoreTests {
    let now = iso("2026-10-06T10:00:00Z")

    func makeStore(url: URL? = nil) -> Store {
        let fixed = now
        return Store(persistence: url.map { Persistence(url: $0) }, now: { fixed }, calendar: utc)
    }

    @Test func addTaskRejectsBlankAndDefaultsToInbox() throws {
        let store = makeStore()
        #expect(store.addTask("   ") == nil)
        let t = try #require(store.addTask("  Buy milk "))
        #expect(t.title == "Buy milk")
        #expect(t.projectID == store.data.inbox.id)
        #expect(store.addTask("x", projectID: UUID())?.projectID == store.data.inbox.id)
    }

    @Test func quickAddUsesPickedTimeUnlessTextHasOne() throws {
        let store = makeStore()
        let picked = iso("2026-10-08T15:30:00Z")
        let a = try #require(store.quickAdd("Submit report", defaultProjectID: nil, inToday: false, remindAt: picked))
        #expect(a.remindAt == picked)
        let b = try #require(store.quickAdd("Call Ana tomorrow 5pm", defaultProjectID: nil, inToday: false, remindAt: picked))
        #expect(b.remindAt != picked)
        #expect(b.title == "Call Ana")
    }

    @Test func quickAddUsesDefaultProjectAndTodayFlag() throws {
        let store = makeStore()
        let work = try #require(store.addProject(name: "Work", color: .green, emoji: "💼"))
        let a = try #require(store.quickAdd("Write report", defaultProjectID: work.id, inToday: true))
        #expect(a.projectID == work.id)
        #expect(a.inToday)
        let b = try #require(store.quickAdd("File it #inbox", defaultProjectID: work.id, inToday: false))
        #expect(b.projectID == store.data.inbox.id)
        #expect(b.title == "File it")
    }

    @Test func completingStampsTimeAndLeavesToday() throws {
        let store = makeStore()
        let t = try #require(store.addTask("Ship", inToday: true))
        store.toggleDone(t.id)
        var got = try #require(store.task(t.id))
        #expect(got.isDone)
        #expect(got.completedAt == now)
        #expect(!got.inToday)
        store.toggleDone(t.id)
        got = try #require(store.task(t.id))
        #expect(!got.isDone)
        #expect(got.completedAt == nil)
    }

    @Test func completeIsIdempotent() throws {
        let store = makeStore()
        let t = try #require(store.addTask("Once"))
        store.complete(t.id)
        store.complete(t.id)
        #expect(store.task(t.id)?.isDone == true)
    }

    @Test func parentAndSubtaskCompletionAreIndependent() throws {
        let store = makeStore()
        let parent = try #require(store.addTask("Parent"))
        let sub = try #require(store.addSubtask(parent.id, title: "child"))
        store.toggleDone(parent.id)
        #expect(store.task(parent.id)?.subtasks.first?.isDone == false)
        let other = try #require(store.addTask("Other"))
        let only = try #require(store.addSubtask(other.id, title: "only"))
        store.toggleSubtask(other.id, only.id)
        #expect(store.task(other.id)?.isDone == false)
        _ = sub
    }

    @Test func snoozeMovesReminder() throws {
        let store = makeStore()
        let t = try #require(store.addTask("Call"))
        store.snooze(t.id, .tenMinutes)
        #expect(store.task(t.id)?.remindAt == iso("2026-10-06T10:10:00Z"))
        store.snooze(t.id, .oneHour)
        #expect(store.task(t.id)?.remindAt == iso("2026-10-06T11:00:00Z"))
        store.snooze(t.id, .tomorrowMorning)
        #expect(store.task(t.id)?.remindAt == iso("2026-10-07T09:00:00Z"))
    }

    @Test func deleteProjectCascadesButInboxIsProtected() throws {
        let store = makeStore()
        let work = try #require(store.addProject(name: "Work", color: .green, emoji: nil))
        store.addTask("w", projectID: work.id)
        store.addTask("i")
        store.deleteProject(store.data.inbox.id)
        #expect(store.data.projects.count == 2)
        store.deleteProject(work.id)
        #expect(store.data.projects.count == 1)
        #expect(store.data.tasks.map(\.title) == ["i"])
    }

    @Test func moveTasksReordersOnlyThatProjectsSlots() throws {
        let store = makeStore()
        let work = try #require(store.addProject(name: "Work", color: .green, emoji: nil))
        let a = try #require(store.addTask("a", projectID: work.id))
        store.addTask("d")
        let b = try #require(store.addTask("b", projectID: work.id))
        let c = try #require(store.addTask("c", projectID: work.id))
        store.moveTasks([a.id, b.id, c.id], fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(store.data.tasks.map(\.title) == ["c", "d", "a", "b"])
    }

    @Test func moveProjectsReorders() throws {
        let store = makeStore()
        store.addProject(name: "A", color: .red, emoji: nil)
        store.addProject(name: "B", color: .blue, emoji: nil)
        store.moveProjects(fromOffsets: IndexSet(integer: 2), toOffset: 1)
        #expect(store.data.projects.map(\.name) == ["Inbox", "B", "A"])
    }

    @Test func moveTaskToAnotherProject() throws {
        let store = makeStore()
        let work = try #require(store.addProject(name: "Work", color: .green, emoji: nil))
        let t = try #require(store.addTask("t"))
        store.move(t.id, toProject: work.id)
        #expect(store.task(t.id)?.projectID == work.id)
        store.move(t.id, toProject: UUID())
        #expect(store.task(t.id)?.projectID == work.id)
    }

    @Test func subtaskLifecycle() throws {
        let store = makeStore()
        let t = try #require(store.addTask("Sprint"))
        #expect(store.addSubtask(t.id, title: "  ") == nil)
        let s = try #require(store.addSubtask(t.id, title: "Estimate"))
        store.toggleSubtask(t.id, s.id)
        #expect(store.task(t.id)?.subtasks.first?.isDone == true)
        store.renameSubtask(t.id, s.id, to: "Estimate stories")
        store.renameSubtask(t.id, s.id, to: " ")
        #expect(store.task(t.id)?.subtasks.first?.title == "Estimate stories")
        store.deleteSubtask(t.id, s.id)
        #expect(store.task(t.id)?.subtasks.isEmpty == true)
    }

    @Test func projectNamesAndEmojiAreCleaned() throws {
        let store = makeStore()
        #expect(store.addProject(name: "  ", color: .red, emoji: nil) == nil)
        var p = try #require(store.addProject(name: " Sprint ", color: .yellow, emoji: "🚀🎉"))
        #expect(p.name == "Sprint")
        #expect(p.emoji == "🚀")
        p.emoji = ""
        p.color = .purple
        store.updateProject(p)
        #expect(store.project(p.id)?.emoji == nil)
        #expect(store.project(p.id)?.color == .purple)
        var inbox = store.data.inbox
        inbox.isInbox = false
        store.updateProject(inbox)
        #expect(store.data.inbox.id == inbox.id)
    }

    @Test func clearDoneRemovesOnlyDoneTasks() throws {
        let store = makeStore()
        let a = try #require(store.addTask("a"))
        let b = try #require(store.addTask("b"))
        store.toggleDone(a.id)
        store.clearDone([a.id, b.id])
        #expect(store.data.tasks.map(\.title) == ["b"])
    }

    @Test func undoRestoresAndRedoReapplies() throws {
        let store = makeStore()
        let t = try #require(store.addTask("Keep me"))
        let um = UndoManager()
        um.groupsByEvent = false
        store.undoManager = um
        um.beginUndoGrouping()
        store.delete(t.id)
        um.endUndoGrouping()
        #expect(store.task(t.id) == nil)
        #expect(um.undoActionName == "Delete Task")
        um.undo()
        #expect(store.task(t.id) != nil)
        um.redo()
        #expect(store.task(t.id) == nil)
    }

    @Test func onChangeFiresOnlyForRealChanges() throws {
        let store = makeStore()
        var count = 0
        store.onChange = { count += 1 }
        let t = try #require(store.addTask("A"))
        #expect(count == 1)
        store.rename(t.id, to: "A")
        #expect(count == 1)
        store.rename(t.id, to: "B")
        #expect(count == 2)
        store.deleteProject(store.data.inbox.id)
        #expect(count == 2)
    }

    @Test func savedDataSurvivesRelaunch() throws {
        let url = tempURL()
        let a = makeStore(url: url)
        let t = try #require(a.addTask("Survive", remindAt: iso("2026-10-07T09:00:00Z")))
        a.addSubtask(t.id, title: "step")
        a.saveNow()
        let b = makeStore(url: url)
        #expect(b.data == a.data)
        #expect(b.loadIssue == nil)
    }

    @Test func saveFailureIsReportedAndRetried() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("metodo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let blocker = dir.appendingPathComponent("blocker")
        try Data().write(to: blocker)            // a file where the data folder should be
        let store = makeStore(url: blocker.appendingPathComponent("data.json"))
        store.addTask("Precious")
        store.saveNow()
        #expect(store.saveError != nil)
        #expect(store.data.tasks.count == 1)
        try FileManager.default.removeItem(at: blocker)
        store.saveNow()
        #expect(store.saveError == nil)
    }

    @Test func corruptFileIsReportedAtLaunch() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{".utf8).write(to: url)
        let store = makeStore(url: url)
        #expect(store.loadIssue?.contains("data-corrupt-") == true)
        #expect(store.data.projects.count == 1)
    }
}

@MainActor
@Suite struct HistoryTests {
    let now = iso("2026-10-06T10:00:00Z")

    func makeStore(url: URL? = nil, at time: @escaping () -> Date) -> Store {
        Store(persistence: url.map { Persistence(url: $0) }, now: time, calendar: utc)
    }

    @Test func newTasksRecordWhenTheyWereCreated() throws {
        let fixed = now
        let store = makeStore(at: { fixed })
        let t = try #require(store.addTask("Write"))
        #expect(t.createdAt == now)
    }

    @Test func snoozingIsCounted() throws {
        let fixed = now
        let store = makeStore(at: { fixed })
        let t = try #require(store.addTask("Call"))
        store.snooze(t.id, .tenMinutes)
        store.snooze(t.id, .oneHour)
        #expect(store.task(t.id)?.snoozeCount == 2)
    }

    @Test func clearingDoneArchivesASnapshotForAnalytics() throws {
        var clock = iso("2026-10-06T08:00:00Z")
        let store = makeStore(at: { clock })
        let work = try #require(store.addProject(name: "Work", color: .green, emoji: "💼"))
        let late = try #require(store.addTask("Ship report", projectID: work.id, remindAt: iso("2026-10-06T09:00:00Z")))
        store.addSubtask(late.id, title: "draft")
        let sub2 = try #require(store.addSubtask(late.id, title: "send"))
        store.toggleSubtask(late.id, sub2.id)
        store.snooze(late.id, .tenMinutes)                    // due 08:10
        let open = try #require(store.addTask("Still open"))
        clock = iso("2026-10-06T09:30:00Z")
        store.toggleDone(late.id)
        clock = iso("2026-10-06T18:00:00Z")
        store.clearDone([late.id, open.id])

        #expect(store.data.tasks.map(\.title) == ["Still open"])
        let record = try #require(store.data.archive.first)
        #expect(store.data.archive.count == 1)
        #expect(record.id == late.id)
        #expect(record.title == "Ship report")
        #expect(record.projectID == work.id)
        #expect(record.projectName == "Work")
        #expect(record.projectEmoji == "💼")
        #expect(record.projectColor == .green)
        #expect(record.createdAt == iso("2026-10-06T08:00:00Z"))
        #expect(record.completedAt == iso("2026-10-06T09:30:00Z"))
        #expect(record.dueAt == iso("2026-10-06T08:10:00Z"))
        #expect(record.wasOverdue)
        #expect(record.snoozeCount == 1)
        #expect(record.subtasksDone == 1)
        #expect(record.subtasksTotal == 2)
        #expect(record.clearedAt == iso("2026-10-06T18:00:00Z"))
    }

    @Test func historyOutlivesItsProject() throws {
        let fixed = now
        let store = makeStore(at: { fixed })
        let p = try #require(store.addProject(name: "Old", color: .red, emoji: nil))
        let t = try #require(store.addTask("Done thing", projectID: p.id))
        store.toggleDone(t.id)
        store.clearDone([t.id])
        store.deleteProject(p.id)
        #expect(store.data.archive.first?.projectName == "Old")
    }

    @Test func historyIsSavedAndReloaded() throws {
        let url = tempURL()
        let fixed = now
        let a = makeStore(url: url, at: { fixed })
        let t = try #require(a.addTask("Keep history"))
        a.toggleDone(t.id)
        a.clearDone([t.id])
        a.saveNow()
        let b = makeStore(url: url, at: { fixed })
        #expect(b.data.archive == a.data.archive)
        #expect(b.data.archive.count == 1)
    }

    @Test func filesFromBeforeHistoryStillLoad() throws {
        let json = """
        {"version":1,"projects":[{"id":"6B1E1D3C-1111-4F00-9A00-000000000001","name":"Inbox","color":"gray","emoji":"📥","isInbox":true}],
         "tasks":[{"id":"6B1E1D3C-1111-4F00-9A00-000000000002","projectID":"6B1E1D3C-1111-4F00-9A00-000000000001",
                   "title":"Old task","isDone":false,"inToday":true,"subtasks":[]}]}
        """
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)
        guard case .loaded(let d) = Persistence(url: url).load() else { Issue.record("old file should load"); return }
        #expect(d.tasks.first?.title == "Old task")
        #expect(d.tasks.first?.createdAt == nil)
        #expect(d.tasks.first?.snoozeCount == 0)
        #expect(d.archive.isEmpty)
    }
}
