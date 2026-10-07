import Testing
import Foundation
@testable import MeToDoCore

@Suite struct PersistenceTests {
    @Test func missingFileLoadsFresh() {
        guard case .fresh(let d) = Persistence(url: tempURL()).load() else {
            Issue.record("expected .fresh"); return
        }
        #expect(d.projects.count == 1)
        #expect(d.projects[0].isInbox)
    }

    @Test func saveThenLoadRoundTripsAndWritesBackup() throws {
        let url = tempURL()
        let p = Persistence(url: url)
        var d = AppData.fresh()
        d.tasks = [TaskItem(projectID: d.inbox.id, title: "Café ☕️",
                            remindAt: Date(timeIntervalSince1970: 1_791_300_000),
                            inToday: true, subtasks: [Subtask(title: "x")])]
        try p.save(d)
        guard case .loaded(let back) = p.load() else { Issue.record("expected .loaded"); return }
        #expect(back == d)
        let bak = url.deletingLastPathComponent().appendingPathComponent("data.json.bak")
        #expect(FileManager.default.fileExists(atPath: bak.path))
    }

    @Test func savedFileUsesSpecKeys() throws {
        let url = tempURL()
        var d = AppData.fresh()
        d.tasks = [TaskItem(projectID: d.inbox.id, title: "x", remindAt: Date(timeIntervalSince1970: 1_791_300_000))]
        try Persistence(url: url).save(d)
        let json = try String(contentsOf: url, encoding: .utf8)
        #expect(json.contains("\"version\" : 1"))
        #expect(json.contains("\"isInbox\" : true"))
        #expect(json.contains("\"remindAt\" : \"2026-10-"))
    }

    @Test func corruptFileIsMovedAsideNotOverwritten() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        guard case .corrupt(let d, movedTo: let moved?) = Persistence(url: url).load() else {
            Issue.record("expected .corrupt with a moved file"); return
        }
        #expect(d.projects.count == 1)
        #expect(moved.lastPathComponent.hasPrefix("data-corrupt-"))
        #expect(moved.pathExtension == "json")
        #expect(try String(contentsOf: moved, encoding: .utf8) == "not json")
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
