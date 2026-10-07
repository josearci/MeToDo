import Testing
import Foundation
@testable import MeToDoCore

@Suite struct QueriesTests {
    let now = iso("2026-10-06T10:00:00Z")
    let sprint = Project(name: "Sprint", color: .yellow, emoji: "🚀")
    let work = Project(name: "Work", color: .green, emoji: "💼")

    func data(_ tasks: [TaskItem]) -> AppData {
        var d = AppData.fresh()
        d.projects += [sprint, work]
        d.tasks = tasks
        return d
    }

    @Test func todayMembership() {
        let p = sprint.id
        #expect(Queries.isInToday(TaskItem(projectID: p, title: "pinned", inToday: true), now: now, calendar: utc))
        #expect(Queries.isInToday(TaskItem(projectID: p, title: "later today", remindAt: iso("2026-10-06T23:59:00Z")), now: now, calendar: utc))
        #expect(Queries.isInToday(TaskItem(projectID: p, title: "overdue", remindAt: iso("2026-10-01T09:00:00Z")), now: now, calendar: utc))
        #expect(!Queries.isInToday(TaskItem(projectID: p, title: "tomorrow", remindAt: iso("2026-10-07T00:00:00Z")), now: now, calendar: utc))
        #expect(!Queries.isInToday(TaskItem(projectID: p, title: "done", isDone: true, inToday: true), now: now, calendar: utc))
    }

    @Test func todayOrderIsOverdueThenTimedThenPicks() {
        let d0 = AppData.fresh()
        let inbox = d0.inbox.id
        let a = TaskItem(projectID: sprint.id, title: "A pinned", inToday: true)
        let e = TaskItem(projectID: sprint.id, title: "E pinned future", remindAt: iso("2026-10-08T09:00:00Z"), inToday: true)
        let b = TaskItem(projectID: inbox, title: "B 15:00", remindAt: iso("2026-10-06T15:00:00Z"))
        let c = TaskItem(projectID: inbox, title: "C yesterday", remindAt: iso("2026-10-05T17:00:00Z"))
        let dd = TaskItem(projectID: inbox, title: "D 09:00", remindAt: iso("2026-10-06T09:00:00Z"))
        let f = TaskItem(projectID: inbox, title: "F tomorrow", remindAt: iso("2026-10-07T09:00:00Z"))
        let g = TaskItem(projectID: inbox, title: "G done", isDone: true, inToday: true)
        var d = d0
        d.projects += [sprint]
        d.tasks = [a, e, b, c, dd, f, g]
        #expect(Queries.today(d, now: now, calendar: utc).map(\.title) == ["C yesterday", "D 09:00", "B 15:00", "A pinned", "E pinned future"])
    }

    @Test func upNextIsEverythingOpenOutsideTodayInProjectOrder() {
        let x = TaskItem(projectID: work.id, title: "x")
        let y = TaskItem(projectID: sprint.id, title: "y")
        let z = TaskItem(projectID: sprint.id, title: "z", inToday: true)
        let w = TaskItem(projectID: sprint.id, title: "w", isDone: true)
        #expect(Queries.upNext(data([x, y, z, w]), now: now, calendar: utc).map(\.title) == ["y", "x"])
    }

    @Test func groupedSkipsEmptyProjectsAndKeepsOrder() {
        let tasks = [TaskItem(projectID: work.id, title: "w1"), TaskItem(projectID: sprint.id, title: "s1"),
                     TaskItem(projectID: work.id, title: "w2")]
        let d = data(tasks)
        let groups = Queries.grouped(Queries.open(d), projects: d.projects)
        #expect(groups.map(\.project.name) == ["Sprint", "Work"])
        #expect(groups[1].tasks.map(\.title) == ["w1", "w2"])
    }

    @Test func doneIsMostRecentFirst() {
        let old = TaskItem(projectID: work.id, title: "old", isDone: true, completedAt: iso("2026-10-01T09:00:00Z"))
        let new = TaskItem(projectID: work.id, title: "new", isDone: true, completedAt: iso("2026-10-05T09:00:00Z"))
        #expect(Queries.done(data([old, new])).map(\.title) == ["new", "old"])
        #expect(Queries.openCount(data([old, new, TaskItem(projectID: work.id, title: "o")]), project: work.id) == 1)
    }

    @Test func doneTodayOnlyHasTasksCompletedToday() {
        let today = TaskItem(projectID: work.id, title: "today", isDone: true, completedAt: iso("2026-10-06T08:00:00Z"))
        let earlier = TaskItem(projectID: work.id, title: "earlier", isDone: true, completedAt: iso("2026-10-05T23:00:00Z"))
        let open = TaskItem(projectID: work.id, title: "open")
        #expect(Queries.doneToday(data([today, earlier, open]), now: now, calendar: utc).map(\.title) == ["today"])
    }

    @Test func atBuildsLocalTimes() {
        #expect(Queries.at(hour: 9, daysFromNow: 1, now: now, calendar: utc) == iso("2026-10-07T09:00:00Z"))
        #expect(Queries.at(hour: 0, daysFromNow: 1, now: now, calendar: utc) == iso("2026-10-07T00:00:00Z"))
    }

    @Test(arguments: [
        ("2026-10-06T15:00:00Z", "Today 3:00 PM"),
        ("2026-10-07T09:00:00Z", "Tomorrow 9:00 AM"),
        ("2026-10-05T17:00:00Z", "Yesterday 5:00 PM"),
        ("2026-10-14T09:00:00Z", "Oct 14, 9:00 AM"),
        ("2027-01-02T09:00:00Z", "Jan 2, 2027, 9:00 AM"),
    ])
    func reminderLabels(_ input: String, _ expected: String) {
        #expect(Queries.reminderLabel(iso(input), now: now, calendar: utc, locale: Locale(identifier: "en_US")) == expected)
    }

    @Test func overdueDetection() {
        let late = TaskItem(projectID: work.id, title: "late", remindAt: iso("2026-10-06T09:59:00Z"))
        let doneLate = TaskItem(projectID: work.id, title: "x", isDone: true, remindAt: iso("2026-10-06T09:00:00Z"))
        #expect(Queries.isOverdue(late, now: now))
        #expect(!Queries.isOverdue(doneLate, now: now))
        #expect(Queries.anyOverdue(data([late]), now: now))
        #expect(!Queries.anyOverdue(data([doneLate]), now: now))
    }

    @Test func planHasOnlyOpenFutureRemindersSoonestFirst() {
        let a = TaskItem(projectID: AppData.fresh().inbox.id, title: "a", remindAt: iso("2026-10-06T11:00:00Z"))
        let past = TaskItem(projectID: work.id, title: "past", remindAt: iso("2026-10-06T09:00:00Z"))
        let done = TaskItem(projectID: work.id, title: "done", isDone: true, remindAt: iso("2026-10-06T12:00:00Z"))
        let none = TaskItem(projectID: work.id, title: "none")
        let e = TaskItem(projectID: sprint.id, title: "e", remindAt: iso("2026-10-06T10:30:00Z"))
        var d = data([a, past, done, none, e])
        d.tasks[0].projectID = d.inbox.id
        let plan = Queries.reminderPlan(d, now: now)
        #expect(plan.map(\.title) == ["e", "a"])
        #expect(plan[0].subtitle == "🚀 Sprint")
        #expect(plan[1].subtitle == "📥 Inbox")
    }

    @Test func planIsSoonestFirstAndCapped() {
        let tasks = (1...70).map { TaskItem(projectID: work.id, title: "t\($0)", remindAt: now.addingTimeInterval(Double(71 - $0) * 60)) }
        let plan = Queries.reminderPlan(data(tasks), now: now)
        #expect(plan.count == 64)
        #expect(plan.first?.title == "t70")
    }

    @Test func diffAddsNewAndKeepsExisting() {
        let id = UUID()
        let x = PlannedReminder(taskID: id, date: iso("2026-10-06T11:00:00Z"), title: "x", subtitle: "")
        var r = Queries.reminderDiff(scheduled: [:], plan: [x], now: now)
        #expect(r.add == [x]); #expect(r.remove.isEmpty)
        r = Queries.reminderDiff(scheduled: [id: x], plan: [x], now: now)
        #expect(r.add.isEmpty); #expect(r.remove.isEmpty)
        let moved = PlannedReminder(taskID: id, date: iso("2026-10-06T11:10:00Z"), title: "x", subtitle: "")
        r = Queries.reminderDiff(scheduled: [id: x], plan: [moved], now: now)
        #expect(r.add == [moved]); #expect(r.remove.isEmpty)   // same identifier replaces
    }

    @Test func diffRemovesFutureRemindersThatLeftThePlan() {
        let id = UUID()
        let x = PlannedReminder(taskID: id, date: iso("2026-10-06T11:00:00Z"), title: "x", subtitle: "")
        #expect(Queries.reminderDiff(scheduled: [id: x], plan: [], now: now).remove == [id])
    }

    @Test func diffNeverCancelsAReminderThatJustPassed() {
        let id = UUID()
        let x = PlannedReminder(taskID: id, date: iso("2026-10-06T09:59:59Z"), title: "x", subtitle: "")
        #expect(Queries.reminderDiff(scheduled: [id: x], plan: [], now: now).remove.isEmpty)
    }

    @Test func duplicateProjectIDsDoNotCrash() {
        var d = data([TaskItem(projectID: work.id, title: "t", remindAt: iso("2026-10-06T11:00:00Z"))])
        d.projects.append(work)
        #expect(Queries.open(d).count == 1)
        #expect(Queries.reminderPlan(d, now: now).count == 1)
    }
}
