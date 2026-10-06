import Foundation
import Observation

public enum SnoozeAction: Sendable {
    case tenMinutes, oneHour, tomorrowMorning
}

/// The single source of truth. Every change goes through `mutate`, which records undo,
/// notifies `onChange` (reminders) and schedules a debounced save.
@MainActor @Observable
public final class Store {
    public private(set) var data: AppData
    /// Shown once at launch when the data file couldn't be read.
    public private(set) var loadIssue: String?
    public private(set) var saveError: String?
    @ObservationIgnored public var undoManager: UndoManager?
    @ObservationIgnored public var onChange: (() -> Void)?
    @ObservationIgnored private let persistence: Persistence?
    @ObservationIgnored private var savingDisabled = false
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar

    public init(persistence: Persistence?, now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.persistence = persistence
        self.now = now
        self.calendar = calendar
        var loaded = AppData.fresh()
        var issue: String?
        var disabled = false
        if let persistence {
            switch persistence.load(now: now()) {
            case .fresh(let d), .loaded(let d):
                loaded = d
            case .corrupt(let d, movedTo: let moved?):
                loaded = d
                issue = "Your data file couldn't be read, so MeToDo started with an empty list. The old file was kept at \(moved.path)."
            case .corrupt(let d, movedTo: nil):
                loaded = d
                disabled = true
                issue = "Your data file at \(persistence.url.path) couldn't be read or moved aside. MeToDo won't save changes until that file is fixed or removed."
            }
        }
        loaded.repair()
        self.data = loaded
        self.loadIssue = issue
        self.savingDisabled = disabled
    }

    // MARK: Lookups

    public func task(_ id: UUID) -> TaskItem? { data.tasks.first { $0.id == id } }
    public func project(_ id: UUID) -> Project? { data.projects.first { $0.id == id } }

    // MARK: Tasks

    @discardableResult
    public func addTask(_ title: String, projectID: UUID? = nil, remindAt: Date? = nil, inToday: Bool = false) -> TaskItem? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let pid = projectID.flatMap { project($0)?.id } ?? data.inbox.id
        let task = TaskItem(projectID: pid, title: title, remindAt: remindAt, inToday: inToday, createdAt: now())
        mutate("Add Task") { $0.tasks.append(task) }
        return task
    }

    @discardableResult
    /// `remindAt` is the time picked in the Add field; a time typed in the text wins over it.
    public func quickAdd(_ input: String, defaultProjectID: UUID?, inToday: Bool, remindAt: Date? = nil) -> TaskItem? {
        guard let r = QuickAdd.parse(input, projects: data.projects, calendar: calendar) else { return nil }
        return addTask(r.title, projectID: r.projectID ?? defaultProjectID, remindAt: r.remindAt ?? remindAt, inToday: inToday)
    }

    public func rename(_ id: UUID, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        updateTask(id, "Rename Task") { $0.title = title }
    }

    public func toggleDone(_ id: UUID) {
        let stamp = now()
        updateTask(id, "Complete Task") { t in
            t.isDone.toggle()
            t.completedAt = t.isDone ? stamp : nil
            if t.isDone { t.inToday = false }
        }
    }

    /// Idempotent version for the notification's Complete button.
    public func complete(_ id: UUID) {
        guard let t = task(id), !t.isDone else { return }
        toggleDone(id)
    }

    /// Saved on every keystroke (nothing lost if the app quits mid-typing) but not added to the
    /// task undo stack: the notes text view has its own typing undo.
    public func setNotes(_ id: UUID, _ notes: String) {
        updateTask(id, "Edit Notes", undoable: false) { $0.notes = notes }
    }

    public func toggleToday(_ id: UUID) {
        updateTask(id, "Toggle Today") { $0.inToday.toggle() }
    }

    public func setReminder(_ id: UUID, _ date: Date?) {
        updateTask(id, date == nil ? "Remove Reminder" : "Set Reminder") { $0.remindAt = date }
    }

    public func snooze(_ id: UUID, _ action: SnoozeAction) {
        let n = now()
        let date = switch action {
        case .tenMinutes: n.addingTimeInterval(10 * 60)
        case .oneHour: n.addingTimeInterval(60 * 60)
        case .tomorrowMorning: Queries.at(hour: 9, daysFromNow: 1, now: n, calendar: calendar)
        }
        updateTask(id, "Snooze") { t in
            t.remindAt = date
            t.snoozeCount += 1
        }
    }

    public func move(_ id: UUID, toProject projectID: UUID) {
        guard project(projectID) != nil else { return }
        updateTask(id, "Move Task") { $0.projectID = projectID }
    }

    public func delete(_ id: UUID) {
        mutate("Delete Task") { $0.tasks.removeAll { $0.id == id } }
    }

    /// Removes done tasks from the lists, keeping each one in `data.archive` for analytics.
    public func clearDone(_ ids: [UUID]) {
        let ids = Set(ids)
        let stamp = now()
        mutate("Clear Done") { d in
            let cleared = d.tasks.filter { $0.isDone && ids.contains($0.id) }
            let projects = Dictionary(d.projects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            d.archive += cleared.map { CompletedTask(task: $0, project: projects[$0.projectID], clearedAt: stamp) }
            d.tasks.removeAll { $0.isDone && ids.contains($0.id) }
        }
    }

    /// Reorders the tasks of one list (`displayedIDs`, in display order) like SwiftUI's onMove,
    /// writing them back into the same slots of `data.tasks` so other projects' tasks stay put.
    public func moveTasks(_ displayedIDs: [UUID], fromOffsets: IndexSet, toOffset: Int) {
        mutate("Move Task") { d in
            let slots = displayedIDs.compactMap { id in d.tasks.firstIndex { $0.id == id } }.sorted()
            guard slots.count == displayedIDs.count else { return }
            let items = displayedIDs.compactMap { id in d.tasks.first { $0.id == id } }
            for (slot, item) in zip(slots, Self.moved(items, fromOffsets: fromOffsets, toOffset: toOffset)) {
                d.tasks[slot] = item
            }
        }
    }

    // MARK: Subtasks

    @discardableResult
    public func addSubtask(_ taskID: UUID, title: String) -> Subtask? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, task(taskID) != nil else { return nil }
        let sub = Subtask(title: title)
        updateTask(taskID, "Add Subtask") { $0.subtasks.append(sub) }
        return sub
    }

    public func toggleSubtask(_ taskID: UUID, _ subID: UUID) {
        updateSubtask(taskID, subID, "Complete Subtask") { $0.isDone.toggle() }
    }

    public func renameSubtask(_ taskID: UUID, _ subID: UUID, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        updateSubtask(taskID, subID, "Rename Subtask") { $0.title = title }
    }

    public func deleteSubtask(_ taskID: UUID, _ subID: UUID) {
        updateTask(taskID, "Delete Subtask") { $0.subtasks.removeAll { $0.id == subID } }
    }

    // MARK: Projects

    @discardableResult
    public func addProject(name: String, color: ProjectColor, emoji: String?) -> Project? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let p = Project(name: name, color: color, emoji: Self.cleanEmoji(emoji))
        mutate("Add Project") { $0.projects.append(p) }
        return p
    }

    /// Updates name, color and emoji. `isInbox` can't be changed from outside.
    public func updateProject(_ updated: Project) {
        let name = updated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        mutate("Edit Project") { d in
            guard let i = d.projects.firstIndex(where: { $0.id == updated.id }) else { return }
            d.projects[i].name = name
            d.projects[i].color = updated.color
            d.projects[i].emoji = Self.cleanEmoji(updated.emoji)
        }
    }

    /// Deletes the project and its tasks. The Inbox can't be deleted.
    public func deleteProject(_ id: UUID) {
        guard let p = project(id), !p.isInbox else { return }
        mutate("Delete Project") { d in
            d.projects.removeAll { $0.id == id }
            d.tasks.removeAll { $0.projectID == id }
        }
    }

    public func moveProjects(fromOffsets: IndexSet, toOffset: Int) {
        mutate("Move Project") { $0.projects = Self.moved($0.projects, fromOffsets: fromOffsets, toOffset: toOffset) }
    }

    // MARK: Saving

    public func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        guard let persistence, !savingDisabled else { return }
        do {
            try persistence.save(data)
            saveError = nil
        } catch {
            saveError = "Couldn't save (\(error.localizedDescription)). Your changes are kept and MeToDo will retry on the next change."
        }
    }

    // MARK: Plumbing

    private func mutate(_ name: String, undoable: Bool = true, _ change: (inout AppData) -> Void) {
        let before = data
        change(&data)
        guard data != before else { return }
        if undoable { registerUndo(restoring: before, name) }
        didChange()
    }

    private func updateTask(_ id: UUID, _ name: String, undoable: Bool = true, _ change: (inout TaskItem) -> Void) {
        mutate(name, undoable: undoable) { d in
            if let i = d.tasks.firstIndex(where: { $0.id == id }) { change(&d.tasks[i]) }
        }
    }

    private func updateSubtask(_ taskID: UUID, _ subID: UUID, _ name: String, _ change: (inout Subtask) -> Void) {
        updateTask(taskID, name) { t in
            if let i = t.subtasks.firstIndex(where: { $0.id == subID }) { change(&t.subtasks[i]) }
        }
    }

    /// Snapshot undo: restoring registers the inverse, which gives redo for free.
    private func registerUndo(restoring snapshot: AppData, _ name: String) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated {
                let current = store.data
                store.data = snapshot
                store.registerUndo(restoring: current, name)
                store.didChange()
            }
        }
        undoManager.setActionName(name)
    }

    private func didChange() {
        onChange?()
        guard persistence != nil, !savingDisabled else { return }
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    static func cleanEmoji(_ s: String?) -> String? {
        s?.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init)
    }

    /// Same semantics as SwiftUI's `move(fromOffsets:toOffset:)`, without importing SwiftUI.
    static func moved<T>(_ items: [T], fromOffsets: IndexSet, toOffset: Int) -> [T] {
        let moving = fromOffsets.map { items[$0] }
        var rest = items.enumerated().filter { !fromOffsets.contains($0.offset) }.map(\.element)
        rest.insert(contentsOf: moving, at: toOffset - fromOffsets.count(where: { $0 < toOffset }))
        return rest
    }
}
