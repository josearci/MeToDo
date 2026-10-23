import Foundation

public enum ProjectColor: String, Codable, CaseIterable, Sendable {
    case gray, red, orange, yellow, green, teal, blue, purple
}

public struct Project: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var color: ProjectColor
    public var emoji: String?
    public var isInbox: Bool
    /// A user-picked "#RRGGBB" that overrides the palette `color` when set.
    public var customColor: String?

    public init(id: UUID = UUID(), name: String, color: ProjectColor, emoji: String? = nil, isInbox: Bool = false,
                customColor: String? = nil) {
        self.id = id
        self.name = name
        self.color = color
        self.emoji = emoji
        self.isInbox = isInbox
        self.customColor = customColor
    }

    /// "#4cc38a" / "4CC38A" → "#4CC38A"; anything that isn't 6 hex digits → nil.
    public static func normalizedHex(_ s: String) -> String? {
        var hex = s.trimmingCharacters(in: .whitespaces).uppercased()
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, hex.allSatisfy(\.isHexDigit) else { return nil }
        return "#" + hex
    }

    /// "📥 Inbox", or just the name when there's no emoji.
    public var displayName: String {
        guard let emoji, !emoji.isEmpty else { return name }
        return "\(emoji) \(name)"
    }
}

/// Highest first in Today. Saved by name, so the file stays readable.
public enum Priority: String, Codable, CaseIterable, Comparable, Sendable {
    case none, low, medium, high, urgent

    public static func < (a: Priority, b: Priority) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }

    /// "high", "h", "med", "P1" (= urgent) … "P4" (= low); nil when it's none of those.
    public init?(parsing s: String) {
        let s = s.trimmingCharacters(in: .whitespaces).lowercased()
        let p: [String: Priority] = ["p1": .urgent, "p2": .high, "p3": .medium, "p4": .low]
        guard let found = p[s] ?? (s.isEmpty ? nil : Self.allCases.first { $0.rawValue.hasPrefix(s) }) else { return nil }
        self = found
    }
}

public struct Subtask: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var isDone: Bool
    /// A due day/time of its own; one due today pulls the parent task into Today.
    public var dueAt: Date?
    /// Minutes.
    public var estimate: Int?

    public init(id: UUID = UUID(), title: String, isDone: Bool = false, dueAt: Date? = nil, estimate: Int? = nil) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.dueAt = dueAt
        self.estimate = estimate
    }
}

/// Named TaskItem so it never collides with Swift Concurrency's `Task`.
public struct TaskItem: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var projectID: UUID
    public var title: String
    public var isDone: Bool
    public var completedAt: Date?
    public var remindAt: Date?
    /// Pulled into Today by hand (☀️). Cleared when the task is completed.
    public var inToday: Bool
    public var subtasks: [Subtask]
    /// nil for tasks created before this was tracked.
    public var createdAt: Date?
    public var snoozeCount: Int
    /// Free-form extra information, shown when the task is expanded.
    public var notes: String
    public var priority: Priority
    /// How long it should take, in minutes.
    public var estimate: Int?

    public init(id: UUID = UUID(), projectID: UUID, title: String, isDone: Bool = false,
                completedAt: Date? = nil, remindAt: Date? = nil, inToday: Bool = false,
                subtasks: [Subtask] = [], createdAt: Date? = nil, snoozeCount: Int = 0, notes: String = "",
                priority: Priority = .none, estimate: Int? = nil) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.isDone = isDone
        self.completedAt = completedAt
        self.remindAt = remindAt
        self.inToday = inToday
        self.subtasks = subtasks
        self.createdAt = createdAt
        self.snoozeCount = snoozeCount
        self.notes = notes
        self.priority = priority
        self.estimate = estimate
    }

    /// Fields added later default when missing, so older data files keep loading.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        projectID = try c.decode(UUID.self, forKey: .projectID)
        title = try c.decode(String.self, forKey: .title)
        isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        remindAt = try c.decodeIfPresent(Date.self, forKey: .remindAt)
        inToday = try c.decodeIfPresent(Bool.self, forKey: .inToday) ?? false
        subtasks = try c.decodeIfPresent([Subtask].self, forKey: .subtasks) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        snoozeCount = try c.decodeIfPresent(Int.self, forKey: .snoozeCount) ?? 0
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        // A priority this version doesn't know (hand edit, newer app) reads as none instead of failing the whole file.
        priority = (try? c.decodeIfPresent(Priority.self, forKey: .priority)) ?? .none
        estimate = try c.decodeIfPresent(Int.self, forKey: .estimate)
    }

    public var subtaskProgress: (done: Int, total: Int) {
        (subtasks.filter(\.isDone).count, subtasks.count)
    }
}

/// A finished task that was cleared from the lists, kept for analytics. The project is
/// snapshotted so renaming or deleting it later doesn't rewrite history.
public struct CompletedTask: Codable, Equatable, Identifiable, Sendable {
    /// The original task's id.
    public var id: UUID
    public var title: String
    public var projectID: UUID
    public var projectName: String
    public var projectEmoji: String?
    public var projectColor: ProjectColor
    public var projectCustomColor: String?
    public var createdAt: Date?
    public var completedAt: Date
    /// The reminder time the task had when it was completed.
    public var dueAt: Date?
    /// Completed after it was due.
    public var wasOverdue: Bool
    public var snoozeCount: Int
    public var subtasksDone: Int
    public var subtasksTotal: Int
    public var clearedAt: Date
    /// Optional so history saved before notes existed still loads.
    public var notes: String?

    public init(task: TaskItem, project: Project?, clearedAt: Date) {
        id = task.id
        title = task.title
        projectID = task.projectID
        projectName = project?.name ?? "Deleted project"
        projectEmoji = project?.emoji
        projectColor = project?.color ?? .gray
        projectCustomColor = project?.customColor
        createdAt = task.createdAt
        let completed = task.completedAt ?? clearedAt
        completedAt = completed
        dueAt = task.remindAt
        wasOverdue = task.remindAt.map { completed > $0 } ?? false
        snoozeCount = task.snoozeCount
        (subtasksDone, subtasksTotal) = task.subtaskProgress
        self.clearedAt = clearedAt
        notes = task.notes.isEmpty ? nil : task.notes
    }
}

/// Everything that gets saved. Array order is display order.
public struct AppData: Codable, Equatable, Sendable {
    public var version: Int
    public var projects: [Project]
    public var tasks: [TaskItem]
    /// Completed tasks cleared from the lists, oldest first (analytics history).
    public var archive: [CompletedTask]

    public init(version: Int = 1, projects: [Project], tasks: [TaskItem] = [], archive: [CompletedTask] = []) {
        self.version = version
        self.projects = projects
        self.tasks = tasks
        self.archive = archive
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        projects = try c.decode([Project].self, forKey: .projects)
        tasks = try c.decode([TaskItem].self, forKey: .tasks)
        archive = try c.decodeIfPresent([CompletedTask].self, forKey: .archive) ?? []
    }

    public static func fresh() -> AppData {
        AppData(projects: [makeInbox()])
    }

    /// The Inbox. `repair()` (run on every load) guarantees it exists.
    public var inbox: Project {
        projects.first(where: \.isInbox) ?? Self.makeInbox()
    }

    /// Makes hand-edited or old files safe: puts the Inbox back on top and
    /// re-homes tasks whose project no longer exists.
    public mutating func repair() {
        // Duplicate ids would confuse SwiftUI lists and delete more than intended; later copies
        // get fresh ids (their tasks stay with the first), and only the first Inbox stays the Inbox.
        var seen = Set<UUID>()
        var hasInbox = false
        for i in projects.indices {
            if !seen.insert(projects[i].id).inserted {
                projects[i].id = UUID()
                seen.insert(projects[i].id)
            }
            if projects[i].isInbox {
                if hasInbox { projects[i].isInbox = false }
                hasInbox = true
            }
        }
        seen = []
        for i in tasks.indices where !seen.insert(tasks[i].id).inserted {
            tasks[i].id = UUID()
            seen.insert(tasks[i].id)
        }
        if !projects.contains(where: \.isInbox) {
            projects.insert(Self.makeInbox(), at: 0)
        }
        let known = Set(projects.map(\.id))
        let inboxID = inbox.id
        for i in tasks.indices where !known.contains(tasks[i].projectID) {
            tasks[i].projectID = inboxID
        }
    }

    private static func makeInbox() -> Project {
        Project(name: "Inbox", color: .gray, emoji: "📥", isInbox: true)
    }
}
