import Testing
import Foundation
@testable import MeToDoCore

@Suite struct ModelsTests {
    @Test func freshDataHasOnlyInbox() {
        let d = AppData.fresh()
        #expect(d.version == 1)
        #expect(d.projects.count == 1)
        #expect(d.projects[0].isInbox)
        #expect(d.projects[0].displayName == "📥 Inbox")
        #expect(d.inbox.id == d.projects[0].id)
        #expect(d.tasks.isEmpty)
    }

    @Test func repairRestoresMissingInboxAtTop() {
        var d = AppData(projects: [Project(name: "Work", color: .green)])
        d.repair()
        d.repair()
        #expect(d.projects.count == 2)
        #expect(d.projects[0].isInbox)
        #expect(d.projects[1].name == "Work")
    }

    @Test func repairMovesOrphanTasksToInbox() {
        var d = AppData.fresh()
        d.tasks = [TaskItem(projectID: UUID(), title: "Lost")]
        d.repair()
        #expect(d.tasks[0].projectID == d.inbox.id)
    }

    @Test func repairGivesDuplicateIDsFreshOnes() {
        let work = Project(name: "Work", color: .green)
        var copy = work
        copy.name = "Work copy"
        var d = AppData.fresh()
        d.projects += [work, copy, AppData.fresh().projects[0]]
        let t = TaskItem(projectID: work.id, title: "t")
        d.tasks = [t, t]
        d.repair()
        #expect(Set(d.projects.map(\.id)).count == d.projects.count)
        #expect(d.projects.filter(\.isInbox).count == 1)
        #expect(Set(d.tasks.map(\.id)).count == 2)
        #expect(d.tasks.allSatisfy { $0.projectID == work.id })
    }

    @Test func subtaskProgressCountsDone() {
        let t = TaskItem(projectID: UUID(), title: "Sprint",
                         subtasks: [Subtask(title: "a", isDone: true), Subtask(title: "b")])
        #expect(t.subtaskProgress.done == 1)
        #expect(t.subtaskProgress.total == 2)
    }

    @Test func displayNameWithoutEmojiIsJustName() {
        #expect(Project(name: "Work", color: .green).displayName == "Work")
        #expect(Project(name: "Work", color: .green, emoji: "").displayName == "Work")
    }
}
