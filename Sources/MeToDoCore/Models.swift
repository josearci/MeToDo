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

    public init(id: UUID = UUID(), name: String, color: ProjectColor, emoji: String? = nil, isInbox: Bool = false) {
        self.id = id
        self.name = name
        self.color = color
        self.emoji = emoji
        self.isInbox = isInbox
    }

    /// "📥 Inbox", or just the name when there's no emoji.
    public var displayName: String {
        guard let emoji, !emoji.isEmpty else { return name }
        return "\(emoji) \(name)"
    }
}

public struct Subtask: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var isDone: Bool

    public init(id: UUID = UUID(), title: String, isDone: Bool = false) {
        self.id = id
        self.title = title
        self.isDone = isDone
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

    public init(id: UUID = UUID(), projectID: UUID, title: String, isDone: Bool = false,
                completedAt: Date? = nil, remindAt: Date? = nil, inToday: Bool = false,
                subtasks: [Subtask] = []) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.isDone = isDone
        self.completedAt = completedAt
        self.remindAt = remindAt
        self.inToday = inToday
        self.subtasks = subtasks
    }

    public var subtaskProgress: (done: Int, total: Int) {
        (subtasks.filter(\.isDone).count, subtasks.count)
    }
}

/// Everything that gets saved. Array order is display order.
public struct AppData: Codable, Equatable, Sendable {
    public var version: Int
    public var projects: [Project]
    public var tasks: [TaskItem]

    public init(version: Int = 1, projects: [Project], tasks: [TaskItem] = []) {
        self.version = version
        self.projects = projects
        self.tasks = tasks
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
