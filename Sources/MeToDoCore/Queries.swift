import Foundation

public struct TaskGroup: Identifiable, Sendable {
    public let project: Project
    public let tasks: [TaskItem]
    public var id: UUID { project.id }
}

public struct PlannedReminder: Equatable, Sendable {
    public let taskID: UUID
    public let date: Date
    public let title: String
    public let subtitle: String

    public init(taskID: UUID, date: Date, title: String, subtitle: String) {
        self.taskID = taskID
        self.date = date
        self.title = title
        self.subtitle = subtitle
    }
}

/// Pure read-only views over AppData. Everything takes `now`/`calendar` so it's testable.
public enum Queries {
    // MARK: Status

    public static func isOverdue(_ t: TaskItem, now: Date) -> Bool {
        guard !t.isDone, let r = t.remindAt else { return false }
        return r <= now
    }

    /// Open and either pulled in by hand or due (itself or an open subtask) today or earlier (spec §2).
    public static func isInToday(_ t: TaskItem, now: Date, calendar: Calendar = .current) -> Bool {
        guard !t.isDone else { return false }
        if t.inToday { return true }
        guard let r = nextDue(t) else { return false }
        return r < at(hour: 0, daysFromNow: 1, now: now, calendar: calendar)
    }

    /// The earliest of the task's due time and its open subtasks' due times.
    public static func nextDue(_ t: TaskItem) -> Date? {
        ([t.remindAt] + t.subtasks.filter { !$0.isDone }.map(\.dueAt)).compactMap { $0 }.min()
    }

    public static func anyOverdue(_ data: AppData, now: Date) -> Bool {
        data.tasks.contains { isOverdue($0, now: now) }
    }

    // MARK: Lists

    public static func open(_ data: AppData, project: UUID? = nil) -> [TaskItem] {
        ordered(data.tasks.filter { !$0.isDone && (project == nil || $0.projectID == project) }, projects: data.projects)
    }

    public static func done(_ data: AppData, project: UUID? = nil) -> [TaskItem] {
        data.tasks
            .filter { $0.isDone && (project == nil || $0.projectID == project) }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    /// Tasks completed today, most recent first (the Today view's Done section).
    public static func doneToday(_ data: AppData, now: Date, calendar: Calendar = .current) -> [TaskItem] {
        done(data).filter { $0.completedAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false }
    }

    /// Every finished task, still listed or already cleared, most recent first (the Completed view).
    public static func completed(_ data: AppData) -> [CompletedTask] {
        let projects = Dictionary(data.projects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // ponytail: listed tasks reuse the archive record; clearedAt is just their completion time.
        let listed = done(data).map { CompletedTask(task: $0, project: projects[$0.projectID], clearedAt: $0.completedAt ?? .distantPast) }
        return (listed + data.archive).sorted { $0.completedAt > $1.completedAt }
    }

    public static func openCount(_ data: AppData, project: UUID) -> Int {
        data.tasks.count(where: { !$0.isDone && $0.projectID == project })
    }

    /// Highest priority first; within a priority, earliest effective due time (`nextDue`, so overdue first and
    /// a pinned task due on a later day still counts), undated last; then manual order (project, then list).
    public static func today(_ data: AppData, now: Date, calendar: Calendar = .current) -> [TaskItem] {
        let todays = ordered(data.tasks.filter { isInToday($0, now: now, calendar: calendar) }, projects: data.projects)
        return todays.enumerated().sorted { a, b in
            if a.element.priority != b.element.priority { return a.element.priority > b.element.priority }
            let (ra, rb) = (nextDue(a.element) ?? .distantFuture, nextDue(b.element) ?? .distantFuture)
            if ra != rb { return ra < rb }
            return a.offset < b.offset
        }.map(\.element)
    }

    // MARK: Estimates

    /// Minutes of work left. When subtasks carry estimates they are the breakdown: the open ones are summed
    /// (with `until`, only those due before it or undated, so pieces planned for later days don't count).
    /// Otherwise the task's own estimate. nil when nothing is estimated.
    public static func minutesLeft(_ t: TaskItem, until: Date? = nil) -> Int? {
        guard t.subtasks.contains(where: { $0.estimate != nil }) else { return t.estimate }
        return t.subtasks
            .filter { s in !s.isDone && until.map { (s.dueAt ?? .distantPast) < $0 } ?? true }
            .compactMap(\.estimate).reduce(0, +)
    }

    /// Estimated minutes left today across `tasks` (Today's "5h 30m planned").
    public static func planned(_ tasks: [TaskItem], now: Date, calendar: Calendar = .current) -> Int {
        let endOfToday = at(hour: 0, daysFromNow: 1, now: now, calendar: calendar)
        return tasks.filter { !$0.isDone }.compactMap { minutesLeft($0, until: endOfToday) }.reduce(0, +)
    }

    /// 45 → "45m", 90 → "1h 30m", 120 → "2h".
    public static func durationLabel(_ minutes: Int) -> String {
        let (h, m) = (minutes / 60, minutes % 60)
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// Open tasks not in Today, offered when Today is empty.
    public static func upNext(_ data: AppData, now: Date, calendar: Calendar = .current) -> [TaskItem] {
        ordered(data.tasks.filter { !$0.isDone && !isInToday($0, now: now, calendar: calendar) }, projects: data.projects)
    }

    /// Sidebar project order first, then the order inside data.tasks.
    public static func ordered(_ tasks: [TaskItem], projects: [Project]) -> [TaskItem] {
        let rank = Dictionary(projects.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        return tasks.enumerated().sorted { a, b in
            let ra = rank[a.element.projectID] ?? .max
            let rb = rank[b.element.projectID] ?? .max
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }

    /// One group per project that has tasks, in project order; task order is kept.
    public static func grouped(_ tasks: [TaskItem], projects: [Project]) -> [TaskGroup] {
        let byProject = Dictionary(grouping: tasks, by: \.projectID)
        var seen = Set<UUID>()
        return projects.compactMap { p in
            guard seen.insert(p.id).inserted, let ts = byProject[p.id] else { return nil }
            return TaskGroup(project: p, tasks: ts)
        }
    }

    // MARK: Dates

    public static func at(hour: Int, daysFromNow days: Int, now: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now))!
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }

    /// "Today 3:00 PM", "Tomorrow 9:00 AM", "Yesterday 5:00 PM", "Oct 14, 9:00 AM", "Jan 2, 2027, 9:00 AM".
    public static func reminderLabel(_ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        // ponytail: builds formatters per call; cache them if long lists ever feel slow.
        func format(_ template: String) -> String {
            let f = DateFormatter()
            f.locale = locale
            f.calendar = calendar
            f.timeZone = calendar.timeZone
            f.setLocalizedDateFormatFromTemplate(template)
            return f.string(from: date).replacingOccurrences(of: "\u{202F}", with: " ")
        }
        let time = format("jmm")
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return "Today \(time)"
        case 1: return "Tomorrow \(time)"
        case -1: return "Yesterday \(time)"
        default:
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            return "\(format(sameYear ? "MMMd" : "yMMMd")), \(time)"
        }
    }

    // MARK: Reminders

    /// What should be pending with macOS right now: open tasks with a future reminder, soonest first.
    /// Capped because macOS only keeps a limited number of pending requests per app; the rest get
    /// scheduled as earlier ones pass (the app re-plans every minute).
    public static func reminderPlan(_ data: AppData, now: Date, limit: Int = 64) -> [PlannedReminder] {
        let names = Dictionary(data.projects.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        let plan = data.tasks.compactMap { t -> PlannedReminder? in
            guard !t.isDone, let r = t.remindAt, r > now else { return nil }
            return PlannedReminder(taskID: t.id, date: r, title: t.title, subtitle: names[t.projectID] ?? "")
        }
        return Array(plan.sorted { $0.date < $1.date }.prefix(limit))
    }

    /// Minimal changes to move from what's pending to the plan. Adding with an existing identifier
    /// replaces it. A reminder whose time already passed is never removed: it may be firing right now.
    public static func reminderDiff(scheduled: [UUID: PlannedReminder], plan: [PlannedReminder], now: Date)
        -> (remove: [UUID], add: [PlannedReminder]) {
        let planned = Set(plan.map(\.taskID))
        let remove = scheduled.filter { !planned.contains($0.key) && $0.value.date > now }.map(\.key)
        let add = plan.filter { scheduled[$0.taskID] != $0 }
        return (remove.sorted { $0.uuidString < $1.uuidString }, add)
    }
}
