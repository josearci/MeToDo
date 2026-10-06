# MeToDo macOS App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build MeToDo, a minimal native macOS to-do app with colored projects, one level of subtasks, persistent reminder alerts, a Today view, and a menu bar popover, installed with one command.

**Architecture:** A Swift package with two targets. `MeToDoCore` is pure, fully unit-tested logic: models, JSON persistence, queries (Today, Up next, grouping, reminder planning), the quick-add parser and an `@Observable` `Store` that owns all data and undo. `MeToDo` is the SwiftUI app: a `Window` scene for the main window, a `MenuBarExtra(.window)` for the popover, and an `AppDelegate` that wires up UserNotifications, the login item and a one-minute tick. `install.sh` wraps the release binary into an ad-hoc-signed `.app` in `/Applications`.

**Tech Stack:** Swift 6 toolchain (Swift 5 language mode), SwiftUI, AppKit, Observation, UserNotifications, ServiceManagement, Foundation `NSDataDetector`, Swift Testing. No third-party dependencies.

**Spec:** [`docs/superpowers/specs/2026-10-06-metodo-mac-app-design.md`](../specs/2026-10-06-metodo-mac-app-design.md). The mockups are in `docs/superpowers/specs/mockups/`. Read both before starting.

## Global Constraints

- **Platform and tools:** macOS 15 or later (`platforms: [.macOS(.v15)]`), `swift-tools-version: 6.0`, `swiftLanguageModes: [.v5]`, no third-party dependencies.
- **Bundle id:** `com.josearci.metodo`. It's an agent app (`LSUIElement = true`) with `NSUserNotificationAlertStyle = alert`.
- **Data files:**
  - Data lives at `~/Library/Application Support/MeToDo/data.json`.
  - A backup is written to `data.json.bak` after each successful load.
  - An unreadable file is renamed to `data-corrupt-<yyyyMMdd-HHmmss>.json`, never overwritten.
- **Model naming:** the Swift type for a task is `TaskItem`, never `Task`.
- **UI copy (English, exact strings):**
  - `Add task`, `Add subtask`, `All clear for today`, `Up next`, `Done · n`, `Clear`, `New Project`
  - `Open MeToDo`, `Launch at Login`, `Quit MeToDo`, `Reminders are off · Fix…`
- **Notifications:** category `TASK_REMINDER`, with the actions `Complete`, `Snooze 10 min`, `Snooze 1 hr` and `Tomorrow 9 AM`.
- **Palette:** use the exact dark and light hex values from spec §3. Titles are 58% project color mixed with `#F2F2F4` in dark mode, and 72% mixed with `#1D1D1F` in light mode.
- **Never use `swift run` for the app.** UserNotifications needs a real bundle, so build and launch with `./install.sh`. `swift build` and `swift test` are fine.
- **Commits:** every commit message ends with the line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Stray numbers in Spanish or English titles must not become reminders.** For example, `entrega el 14`, `sprint 42` or `Call 911 contacts` should keep their full title and get no reminder. Pinned by `QuickAddTests.strayNumbersAreNotDates` (Task 4).
2. **More than 64 future reminders.** macOS keeps a limited number of pending requests, so only the soonest 64 are scheduled, and later ones get scheduled as earlier ones pass. Pinned by `QueriesTests.planIsSoonestFirstAndCapped` and `diffAddsNewAndKeepsExisting` (Task 3).
3. **A reminder that just passed must never be cancelled before macOS delivers it.** The diff only removes pending requests whose time is still in the future. Pinned by `QueriesTests.diffNeverCancelsAReminderThatJustPassed` (Task 3).
4. **A hand-edited data file must not crash the app.** This covers a missing Inbox, tasks pointing at a deleted project, and duplicate project ids. The app should repair these on load. Pinned by `ModelsTests.repair*` (Task 1) and `QueriesTests.duplicateProjectIDsDoNotCrash` (Task 3).
5. **Saving fails (disk full, permissions).** Data stays in memory, an error is shown, and the next save retries. Pinned by `StoreTests.saveFailureIsReportedAndRetried` (Task 5).

---

## File Map

```
Package.swift                              Task 1 (core + tests), Task 6 (adds app target)
Sources/MeToDoCore/Models.swift            Task 1  Project, Subtask, TaskItem, AppData, ProjectColor
Sources/MeToDoCore/Persistence.swift       Task 2  load/save JSON, .bak, corrupt handling
Sources/MeToDoCore/Queries.swift           Task 3  Today/Up next/grouping, labels, reminder plan + diff
Sources/MeToDoCore/QuickAdd.swift          Task 4  "Call Ana #sprint tomorrow 9am" parser
Sources/MeToDoCore/Store.swift             Task 5  @Observable store, mutations, undo, debounced save
Tests/MeToDoCoreTests/Helpers.swift        Task 1
Tests/MeToDoCoreTests/ModelsTests.swift    Task 1
Tests/MeToDoCoreTests/PersistenceTests.swift Task 2
Tests/MeToDoCoreTests/QueriesTests.swift   Task 3
Tests/MeToDoCoreTests/QuickAddTests.swift  Task 4
Tests/MeToDoCoreTests/StoreTests.swift     Task 5
Resources/Info.plist                       Task 6
install.sh                                 Task 6
Sources/MeToDo/MeToDoApp.swift             Task 6, Task 8 (commands), Task 10 (reminders env)
Sources/MeToDo/AppDelegate.swift           Task 6, Task 10
Sources/MeToDo/UIState.swift               Task 6
Sources/MeToDo/LoginItem.swift             Task 6
Sources/MeToDo/MenuBarLabel.swift          Task 6, Task 9
Sources/MeToDo/PopoverView.swift           Task 6 (placeholder), Task 9, Task 10
Sources/MeToDo/MainWindow.swift            Task 6 (placeholder), Task 7 (interim), Task 8
Sources/MeToDo/Palette.swift               Task 7
Sources/MeToDo/Components.swift            Task 7  CheckBox, ProgressRing, GroupHeader, AllClear, WarningBanner, rail
Sources/MeToDo/TaskRow.swift               Task 7
Sources/MeToDo/SubtaskList.swift           Task 7
Sources/MeToDo/ReminderPicker.swift        Task 7
Sources/MeToDo/AddField.swift              Task 7
Sources/MeToDo/Sidebar.swift               Task 8
Sources/MeToDo/ProjectEditor.swift         Task 8
Sources/MeToDo/TaskListView.swift          Task 8
Sources/MeToDo/AppCommands.swift           Task 8
Sources/MeToDo/ReminderScheduler.swift     Task 10
README.md                                  Task 11
```

---

### Task 1: Package and data models

**Files:**
- Create: `Package.swift`
- Create: `Sources/MeToDoCore/Models.swift`
- Create: `Tests/MeToDoCoreTests/Helpers.swift`
- Test: `Tests/MeToDoCoreTests/ModelsTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum ProjectColor: String, Codable, CaseIterable, Sendable { gray, red, orange, yellow, green, teal, blue, purple }`
  - `struct Project { id: UUID, name: String, color: ProjectColor, emoji: String?, isInbox: Bool, displayName: String }`
  - `init(id:name:color:emoji:isInbox:)`
  - `struct Subtask { id, title, isDone }`
  - `struct TaskItem { id, projectID, title, isDone, completedAt: Date?, remindAt: Date?, inToday: Bool, subtasks: [Subtask], subtaskProgress: (done: Int, total: Int) }`
  - `struct AppData { version: Int, projects, tasks; static func fresh() -> AppData; var inbox: Project; mutating func repair() }`
  - Test helpers: `utc: Calendar`, `iso(_:) -> Date`, `tempURL() -> URL`

- [ ] **Step 1: Create the package manifest**

`Package.swift`:
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeToDo",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "MeToDoCore"),
        .testTarget(name: "MeToDoCoreTests", dependencies: ["MeToDoCore"]),
    ],
    // ponytail: Swift 5 mode skips strict-concurrency ceremony around AppKit/UserNotifications delegates; move to .v6 if the app ever does real background work.
    swiftLanguageModes: [.v5]
)
```

- [ ] **Step 2: Write test helpers and the failing tests**

`Tests/MeToDoCoreTests/Helpers.swift`:
```swift
import Foundation

/// Gregorian calendar pinned to UTC so date tests don't depend on the machine's time zone.
let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

/// "2026-10-06T10:00:00Z" → Date
func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

/// A data.json path inside a fresh temporary folder (folder not created).
func tempURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("metodo-tests-\(UUID().uuidString)")
        .appendingPathComponent("data.json")
}
```

`Tests/MeToDoCoreTests/ModelsTests.swift`:
```swift
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
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter ModelsTests`
Expected: a build failure, because `MeToDoCore` has no sources yet or because of "cannot find 'AppData' in scope".

- [ ] **Step 4: Implement the models**

`Sources/MeToDoCore/Models.swift`:
```swift
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
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter ModelsTests`
Expected: all 5 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat(core): add package and data models" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Persistence

**Files:**
- Create: `Sources/MeToDoCore/Persistence.swift`
- Test: `Tests/MeToDoCoreTests/PersistenceTests.swift`

**Interfaces:**
- Consumes: `AppData` (Task 1).
- Produces:
  - `struct Persistence { init(url: URL); let url: URL; static var defaultURL: URL }`
  - `func load(now: Date = Date()) -> LoadResult`
  - `func save(_ data: AppData) throws`
  - `enum LoadResult { case fresh(AppData), loaded(AppData), corrupt(AppData, movedTo: URL?) }`

- [ ] **Step 1: Write the failing tests**

`Tests/MeToDoCoreTests/PersistenceTests.swift`:
```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter PersistenceTests`
Expected: FAIL to compile with "cannot find 'Persistence' in scope".

- [ ] **Step 3: Implement persistence**

`Sources/MeToDoCore/Persistence.swift`:
```swift
import Foundation

/// Reads and writes data.json. Never overwrites a file it couldn't read.
public struct Persistence: Sendable {
    public enum LoadResult: Sendable {
        case fresh(AppData)
        case loaded(AppData)
        /// The file was unreadable. `movedTo` is where it was preserved; nil means it
        /// couldn't be moved, so the caller must not save over it.
        case corrupt(AppData, movedTo: URL?)
    }

    public let url: URL

    public init(url: URL) { self.url = url }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeToDo")
            .appendingPathComponent("data.json")
    }

    var backupURL: URL { url.appendingPathExtension("bak") }

    public func load(now: Date = Date()) -> LoadResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return .fresh(.fresh()) }
        do {
            let data = try JSONDecoder.metodo.decode(AppData.self, from: Data(contentsOf: url))
            try? fm.removeItem(at: backupURL)
            try? fm.copyItem(at: url, to: backupURL)
            return .loaded(data)
        } catch {
            let stamp = Self.stamp.string(from: now)
            let dest = url.deletingLastPathComponent().appendingPathComponent("data-corrupt-\(stamp).json")
            do {
                try fm.moveItem(at: url, to: dest)
                return .corrupt(.fresh(), movedTo: dest)
            } catch {
                return .corrupt(.fresh(), movedTo: nil)
            }
        }
    }

    public func save(_ data: AppData) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.metodo.encode(data).write(to: url, options: .atomic)
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()
}

extension JSONEncoder {
    static var metodo: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    static var metodo: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter PersistenceTests`
Expected: all 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MeToDoCore/Persistence.swift Tests/MeToDoCoreTests/PersistenceTests.swift
git commit -m "feat(core): JSON persistence with backup and corrupt-file protection" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Queries (Today, Up next, grouping, labels, reminder plan)

**Files:**
- Create: `Sources/MeToDoCore/Queries.swift`
- Test: `Tests/MeToDoCoreTests/QueriesTests.swift`

**Interfaces:**
- Consumes: `AppData`, `TaskItem`, `Project` (Task 1).
- Produces:
  - `struct TaskGroup: Identifiable { project: Project; tasks: [TaskItem]; id: UUID }`
  - `struct PlannedReminder: Equatable { taskID: UUID; date: Date; title: String; subtitle: String }`
  - `enum Queries` with these static functions:
    - `isOverdue(_:now:) -> Bool`
    - `isInToday(_:now:calendar:) -> Bool`
    - `anyOverdue(_:now:) -> Bool`
    - `open(_:project:) -> [TaskItem]`
    - `done(_:project:) -> [TaskItem]`
    - `openCount(_:project:) -> Int`
    - `today(_:now:calendar:) -> [TaskItem]`
    - `upNext(_:now:calendar:) -> [TaskItem]`
    - `ordered(_:projects:) -> [TaskItem]`
    - `grouped(_:projects:) -> [TaskGroup]`
    - `at(hour:daysFromNow:now:calendar:) -> Date`
    - `reminderLabel(_:now:calendar:locale:) -> String`
    - `reminderPlan(_:now:limit:) -> [PlannedReminder]`
    - `reminderDiff(scheduled:plan:now:) -> (remove: [UUID], add: [PlannedReminder])`

- [ ] **Step 1: Write the failing tests**

`Tests/MeToDoCoreTests/QueriesTests.swift`:
```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter QueriesTests`
Expected: FAIL to compile with "cannot find 'Queries' in scope".

- [ ] **Step 3: Implement the queries**

`Sources/MeToDoCore/Queries.swift`:
```swift
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

    /// Open and either pulled in by hand or with a reminder today or earlier (spec §2).
    public static func isInToday(_ t: TaskItem, now: Date, calendar: Calendar = .current) -> Bool {
        guard !t.isDone else { return false }
        if t.inToday { return true }
        guard let r = t.remindAt else { return false }
        return r < at(hour: 0, daysFromNow: 1, now: now, calendar: calendar)
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

    public static func openCount(_ data: AppData, project: UUID) -> Int {
        data.tasks.count(where: { !$0.isDone && $0.projectID == project })
    }

    /// Spec §6: overdue (oldest first), then later today (by time), then the rest in project order.
    public static func today(_ data: AppData, now: Date, calendar: Calendar = .current) -> [TaskItem] {
        let endOfToday = at(hour: 0, daysFromNow: 1, now: now, calendar: calendar)
        func bucket(_ t: TaskItem) -> Int {
            guard let r = t.remindAt, r < endOfToday else { return 2 }
            return r <= now ? 0 : 1
        }
        let todays = ordered(data.tasks.filter { isInToday($0, now: now, calendar: calendar) }, projects: data.projects)
        return todays.enumerated().sorted { a, b in
            let (ba, bb) = (bucket(a.element), bucket(b.element))
            if ba != bb { return ba < bb }
            if ba < 2, let ra = a.element.remindAt, let rb = b.element.remindAt, ra != rb { return ra < rb }
            return a.offset < b.offset
        }.map(\.element)
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter QueriesTests`
Expected: all tests pass (including the 5 parameterized label cases).

- [ ] **Step 5: Commit**

```bash
git add Sources/MeToDoCore/Queries.swift Tests/MeToDoCoreTests/QueriesTests.swift
git commit -m "feat(core): Today/Up next queries, reminder labels and reminder planning" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Quick-add parser

**Files:**
- Create: `Sources/MeToDoCore/QuickAdd.swift`
- Test: `Tests/MeToDoCoreTests/QuickAddTests.swift`

**Interfaces:**
- Consumes: `Project` (Task 1), `Queries.at` (Task 3, used in tests).
- Produces:
  - `struct QuickAddResult: Equatable { title: String; projectID: UUID?; remindAt: Date? }`
  - `enum QuickAdd` with these static functions:
    - `parse(_ input: String, projects: [Project], calendar: Calendar = .current) -> QuickAddResult?` returns nil when the title would be empty.
    - `matchProject(_ token: String, in: [Project]) -> Project?`
    - `normalize(_ s: String) -> String`

Date phrases are relative to the real clock, because `NSDataDetector` can't take a reference date. The tests compute expectations from `Date()`.

- [ ] **Step 1: Write the failing tests**

`Tests/MeToDoCoreTests/QuickAddTests.swift`:
```swift
import Testing
import Foundation
@testable import MeToDoCore

@Suite struct QuickAddTests {
    let inbox = AppData.fresh().projects[0]
    let sprint = Project(name: "Sprint", color: .yellow, emoji: "🚀")
    let spring = Project(name: "Spring cleaning", color: .green)
    let work = Project(name: "Work", color: .green)
    let workshop = Project(name: "Workshop", color: .blue)
    let ingles = Project(name: "Inglés", color: .purple, emoji: "🎓")
    var all: [Project] { [inbox, sprint, work, workshop, ingles] }

    @Test func projectAndDateAreExtracted() throws {
        let r = try #require(QuickAdd.parse("Call Ana #sprint tomorrow 9am", projects: all))
        #expect(r.title == "Call Ana")
        #expect(r.projectID == sprint.id)
        #expect(r.remindAt == Queries.at(hour: 9, daysFromNow: 1, now: Date()))
    }

    @Test func uniquePrefixMatches() {
        #expect(QuickAdd.parse("Plan #spr", projects: all)?.projectID == sprint.id)
    }

    @Test func ambiguousPrefixStaysInTitle() {
        let r = QuickAdd.parse("Plan #spr", projects: all + [spring])
        #expect(r?.projectID == nil)
        #expect(r?.title == "Plan #spr")
    }

    @Test func exactMatchBeatsPrefix() {
        #expect(QuickAdd.parse("Fix #work", projects: all)?.projectID == work.id)
    }

    @Test func accentsCaseAndEmojiAreIgnored() {
        #expect(QuickAdd.parse("Homework #INGLES", projects: all)?.projectID == ingles.id)
        #expect(QuickAdd.normalize("🎓 Inglés B1") == "inglesb1")
    }

    @Test func spacesInProjectNamesAreIgnored() {
        #expect(QuickAdd.parse("Mop #springcleaning", projects: all + [spring])?.projectID == spring.id)
    }

    @Test func unknownTagStaysInTitle() {
        let r = QuickAdd.parse("Buy milk #nope", projects: all)
        #expect(r?.title == "Buy milk #nope")
        #expect(r?.projectID == nil)
    }

    @Test func dateWithoutTimeDefaultsToNine() throws {
        let r = try #require(QuickAdd.parse("Pay rent friday", projects: all))
        #expect(r.title == "Pay rent")
        let c = Calendar.current.dateComponents([.weekday, .hour, .minute], from: try #require(r.remindAt))
        #expect(c.weekday == 6)
        #expect(c.hour == 9)
        #expect(c.minute == 0)
    }

    @Test func trailingPrepositionIsDropped() throws {
        let r = try #require(QuickAdd.parse("Call Ana at 3pm", projects: all))
        #expect(r.title == "Call Ana")
        #expect(Calendar.current.component(.hour, from: try #require(r.remindAt)) == 15)
    }

    @Test func relativeTimeKeepsDetectedTime() throws {
        let r = try #require(QuickAdd.parse("Stretch in 2 hours", projects: all))
        #expect(r.title == "Stretch")
        let delta = try #require(r.remindAt).timeIntervalSinceNow
        #expect(abs(delta - 7200) < 120)
    }

    @Test(arguments: ["   ", "#sprint", "tomorrow 9am", "#sprint tomorrow"])
    func emptyTitlesCreateNothing(_ input: String) {
        #expect(QuickAdd.parse(input, projects: all) == nil)
    }

    @Test(arguments: [
        "Crear la presentación para entrega el 14",
        "Crear presentación para clase de inglés (octubre 14)",
        "Poner a funcionar AWS",
        "Subir 3 archivos",
        "Revisar sprint 42",
        "Call 911 contacts",
    ])
    func strayNumbersAreNotDates(_ input: String) {
        let r = QuickAdd.parse(input, projects: all)
        #expect(r?.remindAt == nil)
        #expect(r?.title == input)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter QuickAddTests`
Expected: FAIL to compile with "cannot find 'QuickAdd' in scope".

- [ ] **Step 3: Implement the parser**

`Sources/MeToDoCore/QuickAdd.swift`:
```swift
import Foundation

public struct QuickAddResult: Equatable, Sendable {
    public var title: String
    public var projectID: UUID?
    public var remindAt: Date?
}

/// Parses "Call Ana #sprint tomorrow 9am" (spec §7). English date phrases are the supported set.
public enum QuickAdd {
    public static func parse(_ input: String, projects: [Project], calendar: Calendar = .current) -> QuickAddResult? {
        var text = input
        var projectID: UUID?
        if let r = text.range(of: #"#\S+"#, options: .regularExpression),
           let p = matchProject(String(text[r].dropFirst()), in: projects) {
            projectID = p.id
            text.replaceSubrange(r, with: " ")
        }
        var remindAt: Date?
        if let found = detectDate(in: text) {
            let (date, r) = found
            remindAt = hasTime(String(text[r])) ? date : calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date)
            text = dropTrailingPreposition(String(text[..<r.lowerBound])) + " " + text[r.upperBound...]
        }
        let title = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return title.isEmpty ? nil : QuickAddResult(title: title, projectID: projectID, remindAt: remindAt)
    }

    /// Exact normalized name wins; otherwise a prefix that matches exactly one project.
    public static func matchProject(_ token: String, in projects: [Project]) -> Project? {
        let t = normalize(token)
        guard !t.isEmpty else { return nil }
        if let exact = projects.first(where: { normalize($0.name) == t }) { return exact }
        let prefixed = projects.filter { normalize($0.name).hasPrefix(t) }
        return prefixed.count == 1 ? prefixed[0] : nil
    }

    /// Lowercase, accents removed, only letters and digits: "🎓 Inglés B1" → "inglesb1".
    public static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        return String(String.UnicodeScalarView(folded.unicodeScalars.filter(CharacterSet.alphanumerics.contains)))
    }

    /// A detector match only counts if it contains a real date/time word, so bare numbers in
    /// titles ("entrega el 14", "sprint 42") never turn into reminders.
    static let dateWords = #"(?i)\b(today|tonight|tomorrow|yesterday|next|this|mon|tue|wed|thu|fri|sat|sun|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec|noon|midnight|morning|afternoon|evening)|\d\s*(am|pm|a\.m\.|p\.m\.)|\d:\d\d|\bin\s+\d+\s+(min|hour|day|week)"#

    static let timeWords = #"(?i)\d\s*(am|pm|a\.m\.|p\.m\.)|\d:\d\d|noon|midnight|morning|afternoon|evening|tonight|\bin\s+\d+\s+(min|hour)"#

    static func detectDate(in text: String) -> (Date, Range<String.Index>)? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        for m in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let date = m.date, let r = Range(m.range, in: text) else { continue }
            if text[r].range(of: dateWords, options: .regularExpression) != nil { return (date, r) }
        }
        return nil
    }

    static func hasTime(_ phrase: String) -> Bool {
        phrase.range(of: timeWords, options: .regularExpression) != nil
    }

    /// "Call Ana at" → "Call Ana" once the date after it has been removed.
    static func dropTrailingPreposition(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        for p in [" at", " on", " by"] where trimmed.lowercased().hasSuffix(p) {
            return String(trimmed.dropLast(p.count))
        }
        return trimmed
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter QuickAddTests`
Expected: all pass. If a `strayNumbersAreNotDates` case fails, the detector matched something that `dateWords` accepted. Print `text[r]` for that input and tighten `dateWords`. Don't loosen the test.

- [ ] **Step 5: Commit**

```bash
git add Sources/MeToDoCore/QuickAdd.swift Tests/MeToDoCoreTests/QuickAddTests.swift
git commit -m "feat(core): quick-add parser for #project and natural dates" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Store (mutations, undo, saving)

**Files:**
- Create: `Sources/MeToDoCore/Store.swift`
- Test: `Tests/MeToDoCoreTests/StoreTests.swift`

**Interfaces:**
- Consumes: `AppData`, `Persistence`, `Queries.at`, `QuickAdd.parse`.
- Produces:
  - `enum SnoozeAction { tenMinutes, oneHour, tomorrowMorning }`
  - `@MainActor @Observable final class Store`:
    - **Init:** `init(persistence: Persistence?, now: @escaping () -> Date = Date.init, calendar: Calendar = .current)`
    - **State:** `data: AppData` (read-only), `loadIssue: String?`, `saveError: String?`
    - **Hooks:** `var undoManager: UndoManager?`, `var onChange: (() -> Void)?`
    - **Lookups:** `task(_:) -> TaskItem?`, `project(_:) -> Project?`
    - **Tasks:**
      - `addTask(_:projectID:remindAt:inToday:) -> TaskItem?`
      - `quickAdd(_:defaultProjectID:inToday:) -> TaskItem?`
      - `rename(_:to:)`
      - `toggleDone(_:)`, `complete(_:)`
      - `toggleToday(_:)`
      - `setReminder(_:_:)`, `snooze(_:_:)`
      - `move(_:toProject:)`, `delete(_:)`, `clearDone(_:)`
      - `moveTasks(_ displayedIDs: [UUID], fromOffsets: IndexSet, toOffset: Int)`
    - **Subtasks:**
      - `addSubtask(_:title:) -> Subtask?`
      - `toggleSubtask(_:_:)`, `renameSubtask(_:_:to:)`, `deleteSubtask(_:_:)`
    - **Projects:**
      - `addProject(name:color:emoji:) -> Project?`, `updateProject(_:)`
      - `deleteProject(_:)`, `moveProjects(fromOffsets:toOffset:)`
    - **Saving:** `saveNow()`
  - All mutating methods that return a value are `@discardableResult`.

- [ ] **Step 1: Write the failing tests**

`Tests/MeToDoCoreTests/StoreTests.swift`:
```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter StoreTests`
Expected: FAIL to compile with "cannot find 'Store' in scope".

- [ ] **Step 3: Implement the store**

`Sources/MeToDoCore/Store.swift`:
```swift
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
        let task = TaskItem(projectID: pid, title: title, remindAt: remindAt, inToday: inToday)
        mutate("Add Task") { $0.tasks.append(task) }
        return task
    }

    @discardableResult
    public func quickAdd(_ input: String, defaultProjectID: UUID?, inToday: Bool) -> TaskItem? {
        guard let r = QuickAdd.parse(input, projects: data.projects, calendar: calendar) else { return nil }
        return addTask(r.title, projectID: r.projectID ?? defaultProjectID, remindAt: r.remindAt, inToday: inToday)
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
        setReminder(id, date)
    }

    public func move(_ id: UUID, toProject projectID: UUID) {
        guard project(projectID) != nil else { return }
        updateTask(id, "Move Task") { $0.projectID = projectID }
    }

    public func delete(_ id: UUID) {
        mutate("Delete Task") { $0.tasks.removeAll { $0.id == id } }
    }

    public func clearDone(_ ids: [UUID]) {
        let ids = Set(ids)
        mutate("Clear Done") { $0.tasks.removeAll { $0.isDone && ids.contains($0.id) } }
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

    private func mutate(_ name: String, _ change: (inout AppData) -> Void) {
        let before = data
        change(&data)
        guard data != before else { return }
        registerUndo(restoring: before, name)
        didChange()
    }

    private func updateTask(_ id: UUID, _ name: String, _ change: (inout TaskItem) -> Void) {
        mutate(name) { d in
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
```

- [ ] **Step 4: Run the whole core suite**

Run: `swift test`
Expected: every suite passes (Models, Persistence, Queries, QuickAdd, Store).

- [ ] **Step 5: Commit**

```bash
git add Sources/MeToDoCore/Store.swift Tests/MeToDoCoreTests/StoreTests.swift
git commit -m "feat(core): observable store with undo and debounced atomic saves" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: App shell, bundle and installer

**Files:**
- Modify: `Package.swift` (add the app target)
- Create: `Resources/Info.plist`
- Create: `install.sh`
- Create: `Sources/MeToDo/MeToDoApp.swift`
- Create: `Sources/MeToDo/AppDelegate.swift`
- Create: `Sources/MeToDo/UIState.swift`
- Create: `Sources/MeToDo/LoginItem.swift`
- Create: `Sources/MeToDo/MenuBarLabel.swift` (final in Task 9)
- Create: `Sources/MeToDo/PopoverView.swift` (placeholder, replaced in Task 9)
- Create: `Sources/MeToDo/MainWindow.swift` (placeholder, replaced in Task 7)

**Interfaces:**
- Consumes: `Store`, `Persistence.defaultURL` (Tasks 2 and 5).
- Produces:
  - `enum SidebarItem: Hashable { today, all, project(UUID) }`
  - `@MainActor @Observable final class UIState` with these members:
    - `sidebar`, `selectedTaskID: UUID?`, `editingTaskID: UUID?`, `expanded: Set<UUID>`
    - `popoverShowsAll: Bool`, `now: Date`
    - `openMainWindowToken: Int`, `focusAddFieldToken: Int`
    - `showTask(_:)`, `toggleExpanded(_:)`
  - `AppDelegate` with `store: Store`, `ui: UIState` and `undoManager: UndoManager`. It ticks `ui.now` every 60s.
  - `enum LoginItem { static var isOn: Bool; static func set(_ on: Bool) }`
  - The main window is a `Window` scene with id `"main"`.

The app layer has no automated tests (spec §12). Each UI task ends with a build and a manual check of the running app.

- [ ] **Step 1: Add the app target**

Replace the `targets:` array in `Package.swift` with:
```swift
    targets: [
        .target(name: "MeToDoCore"),
        .executableTarget(name: "MeToDo", dependencies: ["MeToDoCore"]),
        .testTarget(name: "MeToDoCoreTests", dependencies: ["MeToDoCore"]),
    ],
```

- [ ] **Step 2: Create the bundle Info.plist**

`Resources/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.josearci.metodo</string>
    <key>CFBundleName</key><string>MeToDo</string>
    <key>CFBundleDisplayName</key><string>MeToDo</string>
    <key>CFBundleExecutable</key><string>MeToDo</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSUserNotificationAlertStyle</key><string>alert</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
```

- [ ] **Step 3: Create the installer**

`install.sh`:
```bash
#!/bin/bash
# Builds MeToDo.app, signs it for this Mac, and (re)installs it in /Applications. Data is untouched.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/MeToDo"
APP=".build/MeToDo.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MeToDo"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

# ponytail: SIGTERM skips applicationWillTerminate; only changes from the last 0.5s (save debounce) could be lost.
pkill -x MeToDo || true
sleep 1
rm -rf /Applications/MeToDo.app
cp -R "$APP" /Applications/
open /Applications/MeToDo.app
echo "Installed /Applications/MeToDo.app"
```
Run: `chmod +x install.sh`

- [ ] **Step 4: Create the shared UI state and the login item helper**

`Sources/MeToDo/UIState.swift`:
```swift
import Foundation
import Observation

enum SidebarItem: Hashable {
    case today, all
    case project(UUID)
}

/// View state shared by the main window, the popover and the menu bar icon.
@MainActor @Observable
final class UIState {
    var sidebar: SidebarItem = .today
    var selectedTaskID: UUID?
    /// Set to a task id to start inline title editing in that row (Return key).
    var editingTaskID: UUID?
    /// Tasks whose subtasks are expanded.
    var expanded: Set<UUID> = []
    var popoverShowsAll = false
    /// Ticks every minute so overdue states and Today roll over on their own.
    var now = Date()
    /// Bumped to ask the always-alive menu bar label to open the main window.
    var openMainWindowToken = 0
    /// Bumped to focus the main window's Add field (⌘N).
    var focusAddFieldToken = 0

    /// Notification click: show the task in the main window.
    func showTask(_ id: UUID) {
        sidebar = .all
        selectedTaskID = id
        openMainWindowToken += 1
    }

    func toggleExpanded(_ id: UUID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }
}
```

`Sources/MeToDo/LoginItem.swift`:
```swift
import Foundation
import ServiceManagement

enum LoginItem {
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }

    /// Failures are logged only; the ⚙︎ toggle reads `isOn` and will simply show off (spec §11).
    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("MeToDo login item: \(error)")
        }
    }
}
```

- [ ] **Step 5: Create the app delegate**

`Sources/MeToDo/AppDelegate.swift`:
```swift
import AppKit
import MeToDoCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store: Store
    let ui: UIState
    /// One app-wide undo stack so ⌘Z works the same from the window and the popover.
    let undoManager = UndoManager()
    private var timer: Timer?

    override init() {
        store = Store(persistence: Persistence(url: Persistence.defaultURL))
        ui = UIState()
        super.init()
        store.undoManager = undoManager
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !UserDefaults.standard.bool(forKey: "didFirstLaunch") {
            UserDefaults.standard.set(true, forKey: "didFirstLaunch")
            LoginItem.set(true)
            ui.openMainWindowToken += 1
        }
        if let issue = store.loadIssue {
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "MeToDo couldn't read its data"
            alert.informativeText = issue
            alert.runModal()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }

    private func tick() {
        ui.now = Date()
    }
}
```

- [ ] **Step 6: Create the app entry point and placeholders**

`Sources/MeToDo/MeToDoApp.swift`:
```swift
import SwiftUI
import MeToDoCore

@main
struct MeToDoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("MeToDo", id: "main") {
            MainWindow()
                .environment(appDelegate.store)
                .environment(appDelegate.ui)
        }
        .defaultSize(width: 880, height: 600)
        .defaultLaunchBehavior(.suppressed)

        MenuBarExtra {
            PopoverView()
                .environment(appDelegate.store)
                .environment(appDelegate.ui)
        } label: {
            MenuBarLabel()
                .environment(appDelegate.store)
                .environment(appDelegate.ui)
        }
        .menuBarExtraStyle(.window)
    }
}
```

`Sources/MeToDo/MenuBarLabel.swift`:
```swift
import SwiftUI
import MeToDoCore

/// The menu bar icon. It's alive for the whole session, so it also opens the main
/// window on request (first launch, notification clicks, ⌘N).
struct MenuBarLabel: View {
    @Environment(UIState.self) private var ui
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "checkmark.circle")
            .onChange(of: ui.openMainWindowToken, initial: true) { _, token in
                guard token > 0 else { return }
                openWindow(id: "main")
                NSApp.activate()
            }
    }
}
```

`Sources/MeToDo/PopoverView.swift` (placeholder):
```swift
import SwiftUI

struct PopoverView: View {
    var body: some View {
        VStack {
            Text("MeToDo")
            Button("Quit MeToDo") { NSApp.terminate(nil) }
        }
        .frame(width: 340, height: 440)
    }
}
```

`Sources/MeToDo/MainWindow.swift` (placeholder):
```swift
import SwiftUI

struct MainWindow: View {
    var body: some View {
        Text("MeToDo")
            .frame(minWidth: 640, minHeight: 420)
            .onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate() }
            .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }
}
```

- [ ] **Step 7: Build, install and check**

Run: `swift build && swift test && ./install.sh`
Expected: the build succeeds, all tests pass, and the script prints "Installed /Applications/MeToDo.app".

Manual check:
1. A ✓ icon appears in the menu bar.
2. On first launch the "MeToDo" window opens and the app shows in the Dock. Closing the window removes the Dock icon, and the menu bar icon stays.
3. Clicking the icon shows the placeholder popover, and Quit MeToDo quits the app.
4. `~/Library/Application Support/MeToDo/` is created after the first change (no change exists yet, so it may still be absent).

To re-test first launch, run `defaults delete com.josearci.metodo didFirstLaunch` and then `./install.sh`.

If the window doesn't open on first launch, the label's `onChange(initial:)` didn't run. Move the same `openWindow` logic into a `.task {}` on the label.

- [ ] **Step 8: Commit**

```bash
git add Package.swift Resources install.sh Sources/MeToDo
git commit -m "feat(app): menu bar agent shell, bundle and one-command installer" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Task row, subtasks, reminder picker and add field

**Files:**
- Create: `Sources/MeToDo/Palette.swift`
- Create: `Sources/MeToDo/Components.swift`
- Create: `Sources/MeToDo/TaskRow.swift`
- Create: `Sources/MeToDo/SubtaskList.swift`
- Create: `Sources/MeToDo/ReminderPicker.swift`
- Create: `Sources/MeToDo/AddField.swift`
- Modify: `Sources/MeToDo/MainWindow.swift` (interim grouped All list, replaced in Task 8)

**Interfaces:**
- Consumes: `Store` API (Task 5), `Queries` (Task 3), `UIState` (Task 6).
- Produces:
  - **Colors:** `ProjectColor.color: Color` and `ProjectColor.titleColor: Color`
  - **Components:** `CheckBox(isOn:color:size:action:)`, `ProgressRing(fraction:color:)`, `GroupHeader(project:)`, `AllClear(hasUpNext:)`, `WarningBanner(text:)`
  - **Modifier:** `View.rail(_ color: ProjectColor)`
  - **Rows:** `TaskRow(task:showProjectTag:alwaysShowSun:compact:)`, `SubtaskList(task:color:)`
  - **Inputs:** `ReminderPicker(taskID:current:)`, `AddField(defaultProjectID:inToday:autofocus:)`

- [ ] **Step 1: Palette (spec §3)**

`Sources/MeToDo/Palette.swift`:
```swift
import SwiftUI
import AppKit
import MeToDoCore

extension ProjectColor {
    private var hex: (dark: UInt32, light: UInt32) {
        switch self {
        case .gray: (0x9A9AA0, 0x8A8A8F)
        case .red: (0xFF6B6B, 0xD93B3B)
        case .orange: (0xFF9F45, 0xC96A12)
        case .yellow: (0xF5C451, 0xC08A12)
        case .green: (0x4CC38A, 0x1F9D63)
        case .teal: (0x4CC9D0, 0x13838A)
        case .blue: (0x5AA9FF, 0x2E6FD1)
        case .purple: (0xA78BFA, 0x7C5CD6)
        }
    }

    /// Full project color: checkboxes, headers, rails, dots.
    var color: Color {
        let hex = hex
        return Color(nsColor: NSColor(name: nil) { $0.isDark ? .hex(hex.dark) : .hex(hex.light) })
    }

    /// Task titles: the project color softened toward the text color (58% dark, 72% light).
    var titleColor: Color {
        let hex = hex
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isDark
                ? NSColor.hex(hex.dark).blended(withFraction: 0.42, of: .hex(0xF2F2F4))!
                : NSColor.hex(hex.light).blended(withFraction: 0.28, of: .hex(0x1D1D1F))!
        })
    }
}

extension NSColor {
    static func hex(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}
```

- [ ] **Step 2: Small shared components**

`Sources/MeToDo/Components.swift`:
```swift
import SwiftUI
import MeToDoCore

/// Rounded-square checkbox in the project color (approved merged design).
struct CheckBox: View {
    let isOn: Bool
    let color: Color
    var size: CGFloat = 14
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: size * 0.36)
                .fill(isOn ? color : .clear)
                .strokeBorder(color, lineWidth: 1.5)
                .overlay {
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: size * 0.6, weight: .bold))
                            .foregroundStyle(.background)
                    }
                }
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "Mark as not done" : "Mark as done")
    }
}

/// The ◔ subtask progress ring.
struct ProgressRing: View {
    let fraction: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.3), lineWidth: 1.5)
            Circle().trim(from: 0, to: fraction).stroke(color, lineWidth: 1.5).rotationEffect(.degrees(-90))
        }
        .frame(width: 9, height: 9)
    }
}

struct GroupHeader: View {
    let project: Project

    var body: some View {
        Text(project.displayName)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(project.color.color)
            .padding(.top, 6)
    }
}

/// Today's empty state (spec §6).
struct AllClear: View {
    let hasUpNext: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "checkmark.circle").font(.system(size: 22))
            Text("All clear for today")
            if hasUpNext {
                Text("Up next · click \(Image(systemName: "sun.max")) to pull into Today")
                    .font(.caption).foregroundStyle(.tertiary).padding(.top, 8)
            }
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }
}

struct WarningBanner: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .padding(8)
            .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            .padding(8)
    }
}

extension View {
    /// The project's 2pt color rail on the leading edge, continuous across rows.
    func rail(_ color: ProjectColor) -> some View {
        padding(.leading, 10)
            .overlay(alignment: .leading) { Rectangle().fill(color.color).frame(width: 2) }
            .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
            .listRowSeparator(.hidden)
    }
}
```

- [ ] **Step 3: Subtask list**

`Sources/MeToDo/SubtaskList.swift`:
```swift
import SwiftUI
import MeToDoCore

/// Indented subtasks plus an "Add subtask" field. Return adds one and keeps focus for the next.
struct SubtaskList: View {
    @Environment(Store.self) private var store
    let task: TaskItem
    let color: ProjectColor
    @State private var newTitle = ""
    @FocusState private var addFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(task.subtasks) { SubtaskRow(taskID: task.id, subtask: $0, color: color) }
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 9)).frame(width: 12)
                TextField("Add subtask", text: $newTitle)
                    .textFieldStyle(.plain)
                    .focused($addFocused)
                    .onSubmit {
                        if store.addSubtask(task.id, title: newTitle) != nil { newTitle = "" }
                        addFocused = true
                    }
            }
            .foregroundStyle(.tertiary)
        }
        .font(.system(size: 12.5))
        .padding(.vertical, 2)
        .onAppear { if task.subtasks.isEmpty { addFocused = true } }
    }
}

private struct SubtaskRow: View {
    @Environment(Store.self) private var store
    let taskID: UUID
    let subtask: Subtask
    let color: ProjectColor
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        HStack(spacing: 8) {
            CheckBox(isOn: subtask.isDone, color: color.color, size: 12) { store.toggleSubtask(taskID, subtask.id) }
            if editing {
                TextField("Subtask", text: $draft)
                    .textFieldStyle(.plain)
                    .onSubmit(commit)
                    .onExitCommand { editing = false }
            } else {
                Text(subtask.title)
                    .strikethrough(subtask.isDone)
                    .foregroundStyle(subtask.isDone ? .secondary : .primary)
                    .onTapGesture { draft = subtask.title; editing = true }
            }
        }
        .contextMenu {
            Button("Delete Subtask", role: .destructive) { store.deleteSubtask(taskID, subtask.id) }
        }
    }

    /// Clearing the text deletes the subtask.
    private func commit() {
        if draft.trimmingCharacters(in: .whitespaces).isEmpty {
            store.deleteSubtask(taskID, subtask.id)
        } else {
            store.renameSubtask(taskID, subtask.id, to: draft)
        }
        editing = false
    }
}
```

- [ ] **Step 4: Reminder picker**

`Sources/MeToDo/ReminderPicker.swift`:
```swift
import SwiftUI
import MeToDoCore

struct ReminderPicker: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let taskID: UUID
    let current: Date?
    @State private var custom: Date

    init(taskID: UUID, current: Date?) {
        self.taskID = taskID
        self.current = current
        _custom = State(initialValue: current ?? Date().addingTimeInterval(3600))
    }

    var body: some View {
        let now = Date()
        VStack(alignment: .leading, spacing: 6) {
            preset("In 1 hour", now.addingTimeInterval(3600))
            if Calendar.current.component(.hour, from: now) < 18 {
                preset("This evening (6 PM)", Queries.at(hour: 18, daysFromNow: 0, now: now))
            }
            preset("Tomorrow 9 AM", Queries.at(hour: 9, daysFromNow: 1, now: now))
            Divider()
            DatePicker("Custom", selection: $custom).labelsHidden()
            HStack {
                if current != nil { Button("Remove", role: .destructive) { set(nil) } }
                Spacer()
                Button("Set") { set(custom) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 240)
    }

    private func preset(_ title: String, _ date: Date) -> some View {
        Button { set(date) } label: {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderless)
    }

    private func set(_ date: Date?) {
        store.setReminder(taskID, date)
        dismiss()
    }
}
```

- [ ] **Step 5: Task row**

`Sources/MeToDo/TaskRow.swift`:
```swift
import SwiftUI
import MeToDoCore

/// One task, shared by the main window and the popover (spec §4, §5).
struct TaskRow: View {
    @Environment(Store.self) private var store
    @Environment(UIState.self) private var ui
    let task: TaskItem
    /// Popover's Today list shows the project as a small tag instead of group headers.
    var showProjectTag = false
    /// Up next always shows ☀️ so a task can be pulled into Today.
    var alwaysShowSun = false
    var compact = false

    @State private var hovering = false
    @State private var editing = false
    @State private var draft = ""
    @State private var pendingDone = false
    @State private var doneGeneration = 0
    @State private var showReminder = false
    @FocusState private var titleFocused: Bool

    private var project: Project? { store.project(task.projectID) }
    private var color: ProjectColor { project?.color ?? .gray }
    private var isExpanded: Bool { ui.expanded.contains(task.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 10) {
                CheckBox(isOn: task.isDone || pendingDone, color: color.color, size: compact ? 13 : 14, action: toggleDone)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    title
                    meta
                }
                Spacer(minLength: 8)
                if !task.isDone && (hovering || alwaysShowSun) { actions }
            }
            if isExpanded {
                SubtaskList(task: task, color: color).padding(.leading, 24)
            }
        }
        .font(.system(size: compact ? 12.5 : 13))
        .padding(.vertical, compact ? 4 : 5)
        .opacity(pendingDone ? 0.4 : 1)
        .animation(.easeOut(duration: 0.2), value: pendingDone)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .popover(isPresented: $showReminder, arrowEdge: .trailing) {
            ReminderPicker(taskID: task.id, current: task.remindAt)
        }
        .onChange(of: ui.editingTaskID) { _, id in
            guard id == task.id else { return }
            ui.editingTaskID = nil
            beginEditing()
        }
        .contextMenu { contextMenu }
    }

    @ViewBuilder private var title: some View {
        if editing {
            TextField("Task", text: $draft)
                .textFieldStyle(.plain)
                .focused($titleFocused)
                .onSubmit(commitEdit)
                .onExitCommand { editing = false }
                .onChange(of: titleFocused) { _, focused in if !focused { commitEdit() } }
        } else {
            Text(task.title)
                .foregroundStyle(task.isDone ? AnyShapeStyle(.secondary) : AnyShapeStyle(color.titleColor))
                .strikethrough(task.isDone)
                .onTapGesture(perform: beginEditing)
        }
    }

    @ViewBuilder private var meta: some View {
        let progress = task.subtaskProgress
        let tag = showProjectTag ? project : nil
        if progress.total > 0 || task.remindAt != nil || task.inToday || tag != nil {
            HStack(spacing: 10) {
                if progress.total > 0 {
                    Button { ui.toggleExpanded(task.id) } label: {
                        HStack(spacing: 4) {
                            ProgressRing(fraction: Double(progress.done) / Double(progress.total), color: color.color)
                            Text("\(progress.done)/\(progress.total)")
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(color.color)
                }
                if let remindAt = task.remindAt {
                    Label(Queries.reminderLabel(remindAt, now: ui.now), systemImage: "bell")
                        .foregroundStyle(Queries.isOverdue(task, now: ui.now) ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                }
                if task.inToday && tag == nil {
                    Image(systemName: "sun.max.fill").foregroundStyle(.yellow)
                }
                if let tag {
                    Text(tag.displayName).foregroundStyle(color.color)
                }
            }
            .font(.system(size: compact ? 10.5 : 11))
            .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button { store.toggleToday(task.id) } label: {
                Image(systemName: task.inToday ? "sun.max.fill" : "sun.max")
            }
            .foregroundStyle(task.inToday ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
            .help(task.inToday ? "Remove from Today (⌘T)" : "Add to Today (⌘T)")
            if hovering {
                Button { showReminder = true } label: {
                    Image(systemName: task.remindAt == nil ? "bell" : "bell.fill")
                }
                .foregroundStyle(.secondary)
                .help("Reminder")
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var contextMenu: some View {
        Button(task.inToday ? "Remove from Today" : "Add to Today") { store.toggleToday(task.id) }
        Button("Add Subtask") { ui.expanded.insert(task.id) }
        Button("Set Reminder…") { showReminder = true }
        Menu("Move to") {
            ForEach(store.data.projects) { p in
                Button(p.displayName) { store.move(task.id, toProject: p.id) }
                    .disabled(p.id == task.projectID)
            }
        }
        Divider()
        Button("Delete", role: .destructive) { store.delete(task.id) }
    }

    private func beginEditing() {
        guard !task.isDone else { return }
        draft = task.title
        editing = true
        DispatchQueue.main.async { titleFocused = true }
    }

    private func commitEdit() {
        guard editing else { return }
        editing = false
        store.rename(task.id, to: draft)
    }

    /// Ticking fades the row for ~1s before it moves to Done; clicking again cancels (spec §4).
    private func toggleDone() {
        if task.isDone { store.toggleDone(task.id); return }
        doneGeneration += 1
        if pendingDone { pendingDone = false; return }
        pendingDone = true
        let generation = doneGeneration
        Task {
            try? await Task.sleep(for: .seconds(1))
            guard pendingDone, generation == doneGeneration else { return }
            pendingDone = false
            store.toggleDone(task.id)
        }
    }
}
```

- [ ] **Step 6: Add field with `#project` autocomplete**

`Sources/MeToDo/AddField.swift`:
```swift
import SwiftUI
import MeToDoCore

/// "Add task" input. Understands `#project` and dates via Store.quickAdd (spec §7).
struct AddField: View {
    @Environment(Store.self) private var store
    @Environment(UIState.self) private var ui
    let defaultProjectID: UUID?
    let inToday: Bool
    var autofocus = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !suggestions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(suggestions.prefix(6)) { p in
                        Button(p.displayName) { complete(with: p) }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(p.color.color)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(p.color.color.opacity(0.12), in: Capsule())
                    }
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "plus").foregroundStyle(.secondary)
                TextField("Add task", text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(submit)
                    .onKeyPress(.tab) {
                        guard let first = suggestions.first else { return .ignored }
                        complete(with: first)
                        return .handled
                    }
                if text.isEmpty {
                    Text("#project · tomorrow 9am").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
        }
        .onChange(of: ui.focusAddFieldToken) { focused = true }
        .onAppear { if autofocus { focused = true } }
    }

    /// The `#partial` being typed as the last word, if any.
    private var partialTag: String? {
        guard let last = text.split(separator: " ", omittingEmptySubsequences: false).last,
              last.hasPrefix("#") else { return nil }
        return String(last.dropFirst())
    }

    private var suggestions: [Project] {
        guard let partial = partialTag else { return [] }
        let n = QuickAdd.normalize(partial)
        return store.data.projects.filter { n.isEmpty || QuickAdd.normalize($0.name).hasPrefix(n) }
    }

    /// Replace the partial tag with the normalized name so the parser matches it exactly.
    private func complete(with p: Project) {
        guard let partial = partialTag else { return }
        text = String(text.dropLast(partial.count + 1)) + "#" + QuickAdd.normalize(p.name) + " "
    }

    private func submit() {
        if partialTag != nil, let first = suggestions.first { complete(with: first); return }
        guard store.quickAdd(text, defaultProjectID: defaultProjectID, inToday: inToday) != nil else { return }
        text = ""
        focused = true
    }
}
```

- [ ] **Step 7: Interim main window (grouped All list)**

Replace `Sources/MeToDo/MainWindow.swift`:
```swift
import SwiftUI
import MeToDoCore

/// Interim: grouped All list + Add field, so Task 7's components can be checked. Replaced in Task 8.
struct MainWindow: View {
    @Environment(Store.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(Queries.grouped(Queries.open(store.data), projects: store.data.projects)) { g in
                    Section {
                        ForEach(g.tasks) { TaskRow(task: $0).rail(g.project.color) }
                    } header: {
                        GroupHeader(project: g.project).rail(g.project.color)
                    }
                }
            }
            .listStyle(.plain)
            AddField(defaultProjectID: nil, inToday: false).padding(16)
        }
        .frame(minWidth: 640, minHeight: 420)
        .onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate() }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }
}
```

- [ ] **Step 8: Build, install and check**

Run: `swift build && ./install.sh`, then open the window with `defaults delete com.josearci.metodo didFirstLaunch && ./install.sh`.

Manual check against `docs/superpowers/specs/mockups/main-window.html`:
1. Typing `Call Ana tomorrow 9am` and pressing Return adds an Inbox task showing `🔔 Tomorrow 9:00 AM`.
2. Typing `#` shows project chips (only Inbox for now), and Tab completes `#inbox `.
3. Hovering a row shows ☀️ and 🔔. The 🔔 popover sets and removes reminders.
4. Right-click → Add Subtask expands an "Add subtask" field. Return adds a subtask and keeps focus. The `◔ n/m` control toggles the list.
5. Clicking the checkbox fades the row, and clicking again within 1s cancels. Otherwise the task disappears from the list.
6. Clicking a title edits it inline. Return saves and Esc cancels.
7. Titles are tinted, and the gray rail shows on the Inbox group in both light and dark mode (System Settings › Appearance).

- [ ] **Step 9: Commit**

```bash
git add Sources/MeToDo
git commit -m "feat(app): task row, subtasks, reminder picker and quick-add field" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Main window (sidebar, projects, views, keyboard)

**Files:**
- Create: `Sources/MeToDo/Sidebar.swift`
- Create: `Sources/MeToDo/ProjectEditor.swift`
- Create: `Sources/MeToDo/TaskListView.swift`
- Create: `Sources/MeToDo/AppCommands.swift`
- Modify: `Sources/MeToDo/MainWindow.swift` (final version)
- Modify: `Sources/MeToDo/MeToDoApp.swift` (attach commands)

**Interfaces:**
- Consumes: everything from Task 7, plus `Store`, `Queries` and `UIState`.
- Produces: the final `MainWindow`, and `AppCommands(store:ui:undoManager:)`.

- [ ] **Step 1: Project editor sheet**

`Sources/MeToDo/ProjectEditor.swift`:
```swift
import SwiftUI
import MeToDoCore

/// Create or edit a project: name, one of 8 colors, optional emoji.
struct ProjectEditor: View {
    @Environment(Store.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(\.dismiss) private var dismiss
    let original: Project?
    @State private var name: String
    @State private var emoji: String
    @State private var color: ProjectColor

    init(project: Project?) {
        original = project
        _name = State(initialValue: project?.name ?? "")
        _emoji = State(initialValue: project?.emoji ?? "")
        _color = State(initialValue: project?.color ?? .blue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(original == nil ? "New Project" : "Edit Project").font(.headline)
            TextField("Name", text: $name)
            HStack {
                TextField("Emoji (optional)", text: $emoji).frame(width: 140)
                Button("Pick…") { NSApp.orderFrontCharacterPalette(nil) }.buttonStyle(.borderless)
            }
            HStack(spacing: 10) {
                ForEach(ProjectColor.allCases, id: \.self) { c in
                    Circle().fill(c.color).frame(width: 20, height: 20)
                        .overlay(Circle().strokeBorder(.primary, lineWidth: c == color ? 2 : 0).padding(-4))
                        .onTapGesture { color = c }
                        .accessibilityLabel(c.rawValue.capitalized)
                        .accessibilityAddTraits(c == color ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(original == nil ? "Create" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func save() {
        if var p = original {
            p.name = name
            p.emoji = emoji
            p.color = color
            store.updateProject(p)
        } else if let p = store.addProject(name: name, color: color, emoji: emoji) {
            ui.sidebar = .project(p.id)
        }
        dismiss()
    }
}
```

- [ ] **Step 2: Sidebar**

`Sources/MeToDo/Sidebar.swift`:
```swift
import SwiftUI
import MeToDoCore

/// Today, All, then projects (spec §4). Projects reorder by drag and accept dropped tasks.
struct Sidebar: View {
    @Environment(Store.self) private var store
    @Environment(UIState.self) private var ui
    @State private var editing: Project?
    @State private var creating = false
    @State private var deleting: Project?

    var body: some View {
        let data = store.data
        List(selection: Binding<SidebarItem?>(get: { ui.sidebar }, set: { if let v = $0 { ui.sidebar = v } })) {
            row("Today", count: Queries.today(data, now: ui.now).count) {
                Image(systemName: "sun.max.fill").foregroundStyle(.yellow)
            }
            .tag(Optional(SidebarItem.today))
            row("All", count: Queries.open(data).count) {
                Image(systemName: "tray.full").foregroundStyle(.secondary)
            }
            .tag(Optional(SidebarItem.all))
            Section("Projects") {
                ForEach(data.projects) { p in
                    row(p.displayName, count: Queries.openCount(data, project: p.id)) {
                        Circle().fill(p.color.color).frame(width: 8, height: 8)
                    }
                    .tag(Optional(SidebarItem.project(p.id)))
                    .contextMenu {
                        Button("Edit…") { editing = p }
                        if !p.isInbox { Button("Delete…", role: .destructive) { deleting = p } }
                    }
                    .dropDestination(for: String.self) { ids, _ in
                        let moved = ids.compactMap(UUID.init(uuidString:))
                        moved.forEach { store.move($0, toProject: p.id) }
                        return !moved.isEmpty
                    }
                }
                .onMove { store.moveProjects(fromOffsets: $0, toOffset: $1) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button { creating = true } label: { Label("New Project", systemImage: "plus") }
                .buttonStyle(.borderless)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $editing) { ProjectEditor(project: $0) }
        .sheet(isPresented: $creating) { ProjectEditor(project: nil) }
        .confirmationDialog("Delete \(deleting?.displayName ?? "")?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            presenting: deleting) { p in
            Button("Delete Project and Its Tasks", role: .destructive) {
                if ui.sidebar == .project(p.id) { ui.sidebar = .all }
                store.deleteProject(p.id)
            }
        } message: { p in
            Text("This also deletes its \(Queries.openCount(store.data, project: p.id)) open task(s). You can undo with ⌘Z.")
        }
    }

    private func row(_ title: String, count: Int, @ViewBuilder icon: () -> some View) -> some View {
        HStack(spacing: 8) {
            icon().frame(width: 16)
            Text(title).lineLimit(1)
            Spacer()
            if count > 0 { Text("\(count)").foregroundStyle(.secondary).monospacedDigit() }
        }
    }
}
```

- [ ] **Step 3: Task list (Today, All, project, Done, Up next, keyboard)**

`Sources/MeToDo/TaskListView.swift`:
```swift
import SwiftUI
import MeToDoCore

struct TaskListView: View {
    @Environment(Store.self) private var store
    @Environment(UIState.self) private var ui
    @State private var showDone = false

    private var projectID: UUID? {
        if case .project(let id) = ui.sidebar { id } else { nil }
    }

    var body: some View {
        @Bindable var ui = ui
        let data = store.data
        VStack(spacing: 0) {
            List(selection: $ui.selectedTaskID) {
                switch ui.sidebar {
                case .today:
                    let today = Queries.today(data, now: ui.now)
                    if today.isEmpty {
                        let upNext = Queries.upNext(data, now: ui.now)
                        AllClear(hasUpNext: !upNext.isEmpty).listRowSeparator(.hidden)
                        groups(upNext, movable: false, alwaysShowSun: true)
                    } else {
                        ForEach(today) { TaskRow(task: $0, showProjectTag: true).listRowSeparator(.hidden) }
                    }
                case .all:
                    groups(Queries.open(data), movable: true)
                case .project(let id):
                    groups(Queries.open(data, project: id), movable: true)
                }
                doneSection(doneTasks(data))
            }
            .listStyle(.plain)
            .onKeyPress(.space) { act { store.toggleDone($0) } }
            .onKeyPress(.return) { act { ui.editingTaskID = $0 } }
            .onKeyPress(.delete) { act { store.delete($0); ui.selectedTaskID = nil } }
            .onKeyPress(.rightArrow) { act { ui.expanded.insert($0) } }
            .onKeyPress(.leftArrow) { act { ui.expanded.remove($0) } }

            AddField(defaultProjectID: projectID, inToday: ui.sidebar == .today)
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)
        }
        .navigationTitle(title)
        .navigationSubtitle("\(openCount) open")
    }

    /// Projects in order, each with its header and color rail. Drag to reorder inside a project;
    /// drag onto a sidebar project to move it there.
    @ViewBuilder private func groups(_ tasks: [TaskItem], movable: Bool, alwaysShowSun: Bool = false) -> some View {
        ForEach(Queries.grouped(tasks, projects: store.data.projects)) { g in
            Section {
                ForEach(g.tasks) { t in
                    TaskRow(task: t, alwaysShowSun: alwaysShowSun)
                        .rail(g.project.color)
                        .itemProvider { NSItemProvider(object: t.id.uuidString as NSString) }
                }
                .onMove(perform: movable ? { (from: IndexSet, to: Int) in
                    store.moveTasks(g.tasks.map(\.id), fromOffsets: from, toOffset: to)
                } : nil)
            } header: {
                GroupHeader(project: g.project).rail(g.project.color)
            }
        }
    }

    @ViewBuilder private func doneSection(_ done: [TaskItem]) -> some View {
        if !done.isEmpty {
            Section {
                if showDone {
                    ForEach(done) { TaskRow(task: $0).listRowSeparator(.hidden) }
                }
            } header: {
                HStack {
                    Button { showDone.toggle() } label: {
                        Label("Done · \(done.count)", systemImage: showDone ? "chevron.down" : "chevron.right")
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    if showDone {
                        Button("Clear") { store.clearDone(done.map(\.id)) }.buttonStyle(.borderless)
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 10)
            }
        }
    }

    private func doneTasks(_ data: AppData) -> [TaskItem] {
        switch ui.sidebar {
        case .today:
            Queries.done(data).filter { $0.completedAt.map { Calendar.current.isDate($0, inSameDayAs: ui.now) } ?? false }
        case .all:
            Queries.done(data)
        case .project(let id):
            Queries.done(data, project: id)
        }
    }

    private var title: String {
        switch ui.sidebar {
        case .today: "Today"
        case .all: "All"
        case .project(let id): store.project(id)?.displayName ?? "Project"
        }
    }

    private var openCount: Int {
        switch ui.sidebar {
        case .today: Queries.today(store.data, now: ui.now).count
        case .all: Queries.open(store.data).count
        case .project(let id): Queries.openCount(store.data, project: id)
        }
    }

    private func act(_ f: (UUID) -> Void) -> KeyPress.Result {
        guard let id = ui.selectedTaskID else { return .ignored }
        f(id)
        return .handled
    }
}
```

- [ ] **Step 4: Menu commands (⌘N, ⌘T, ⌘1…⌘9, undo/redo)**

`Sources/MeToDo/AppCommands.swift`:
```swift
import SwiftUI
import AppKit
import MeToDoCore

struct AppCommands: Commands {
    let store: Store
    let ui: UIState
    let undoManager: UndoManager

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Task") {
                ui.openMainWindowToken += 1
                ui.focusAddFieldToken += 1
            }
            .keyboardShortcut("n")
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { undo(redo: false) }.keyboardShortcut("z")
            Button("Redo") { undo(redo: true) }.keyboardShortcut("z", modifiers: [.command, .shift])
        }
        CommandMenu("Task") {
            Button("Toggle Today") { if let id = ui.selectedTaskID { store.toggleToday(id) } }
                .keyboardShortcut("t")
        }
        CommandGroup(before: .sidebar) {
            Button("Today") { ui.sidebar = .today }.keyboardShortcut("1")
            Button("All") { ui.sidebar = .all }.keyboardShortcut("2")
            ForEach(Array(store.data.projects.prefix(7).enumerated()), id: \.element.id) { index, p in
                Button(p.displayName) { ui.sidebar = .project(p.id) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 3))))
            }
            Divider()
        }
    }

    /// A text field being edited keeps its own typing undo; otherwise undo task changes.
    private func undo(redo: Bool) {
        let textUndo = (NSApp.keyWindow?.firstResponder as? NSTextView)?.undoManager
        let canText = redo ? textUndo?.canRedo : textUndo?.canUndo
        let target = canText == true ? textUndo! : undoManager
        if redo { target.redo() } else { target.undo() }
    }
}
```

- [ ] **Step 5: Final main window and commands wiring**

Replace `Sources/MeToDo/MainWindow.swift`:
```swift
import SwiftUI
import MeToDoCore

struct MainWindow: View {
    @Environment(Store.self) private var store

    var body: some View {
        NavigationSplitView {
            Sidebar().navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 280)
        } detail: {
            TaskListView()
        }
        .frame(minWidth: 640, minHeight: 420)
        .overlay(alignment: .bottom) {
            if let error = store.saveError { WarningBanner(text: error).padding(.bottom, 60) }
        }
        // Dock icon only while the window is open (spec §9).
        .onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate() }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }
}
```

In `Sources/MeToDo/MeToDoApp.swift`, add the commands to the `Window` scene, right after `.defaultLaunchBehavior(.suppressed)`:
```swift
        .commands { AppCommands(store: appDelegate.store, ui: appDelegate.ui, undoManager: appDelegate.undoManager) }
```

- [ ] **Step 6: Build, install and check**

Run: `swift build && ./install.sh`, then open the window from the popover placeholder or with `defaults delete com.josearci.metodo didFirstLaunch && ./install.sh`.

Manual check (spec §4):
1. **Projects.** `＋ New Project` creates `🚀 Sprint` (yellow) and selects it. Right-click → Edit… changes the color. Right-click → Delete… asks for confirmation and then removes the project with its tasks. `⌘Z` restores it. Inbox has no Delete option.
2. **Sidebar order.** Projects can be dragged into a new order.
3. **Moving tasks.** Dragging a task onto a sidebar project moves it there, and so does right-click → Move to.
4. **All view.** All shows the groups with their headers and rails, like the mockup. Tasks can be dragged to reorder within a group.
5. **Today.** Today shows ☀️ picks and today's reminders, each with a project tag. Completing everything shows "All clear for today" followed by Up next with visible ☀️ buttons.
6. **Done.** The `▸ Done · n` section expands, and Clear removes those tasks. `⌘Z` brings them back.
7. **Keyboard.**
   - ↑/↓ select, Space completes, Return edits.
   - ⌫ deletes, →/← expand or collapse subtasks.
   - ⌘T toggles Today, ⌘N focuses Add.
   - ⌘1/⌘2/⌘3 switch views.
   - ⌘Z/⇧⌘Z undo and redo. While editing a title, ⌘Z undoes the typing instead.
8. **Defaults.** Adding while a project is selected goes to that project. Adding in Today marks the task ☀️.

If `.itemProvider` stops `.onMove` working in the list, drop `.itemProvider` and rely on right-click → Move to (the spec offers both). Note the decision in the commit message.

- [ ] **Step 7: Commit**

```bash
git add Sources/MeToDo
git commit -m "feat(app): main window with sidebar, projects, Today/Up next, Done and shortcuts" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Menu bar popover and overdue icon

**Files:**
- Modify: `Sources/MeToDo/PopoverView.swift` (final version, without the reminders row, which Task 10 adds)
- Modify: `Sources/MeToDo/MenuBarLabel.swift` (overdue dot)

**Interfaces:**
- Consumes: `TaskRow`, `AddField`, `GroupHeader`, `AllClear`, `WarningBanner` (Task 7), `LoginItem`, `UIState` (Task 6), `Queries`.
- Produces: the final `PopoverView`, and `MenuBarIcon.image(overdue:) -> NSImage`.

- [ ] **Step 1: Popover**

Replace `Sources/MeToDo/PopoverView.swift`:
```swift
import SwiftUI
import MeToDoCore

/// The compact view under the menu bar icon (spec §5, mockups/menubar-popover.html).
struct PopoverView: View {
    @Environment(Store.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var ui = ui
        let data = store.data
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("View", selection: $ui.popoverShowsAll) {
                    Text("Today · \(Queries.today(data, now: ui.now).count)").tag(false)
                    Text("All · \(Queries.open(data).count)").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Button(action: openMain) { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(.borderless)
                    .help("Open MeToDo (⌘O)")
            }
            .padding([.horizontal, .top], 12)
            .padding(.bottom, 8)

            AddField(defaultProjectID: nil, inToday: !ui.popoverShowsAll, autofocus: true)
                .padding(.horizontal, 12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) { content(data) }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }

            if let error = store.saveError { WarningBanner(text: error) }
            Divider()
            footer
        }
        .frame(width: 340, height: 440)
        .background {
            // ⌘1 / ⌘2 switch tabs (spec §5).
            Group {
                Button("") { ui.popoverShowsAll = false }.keyboardShortcut("1")
                Button("") { ui.popoverShowsAll = true }.keyboardShortcut("2")
            }
            .opacity(0)
        }
    }

    @ViewBuilder private func content(_ data: AppData) -> some View {
        if ui.popoverShowsAll {
            let groups = Queries.grouped(Queries.open(data), projects: data.projects)
            if groups.isEmpty {
                Text("No tasks yet").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 30)
            }
            ForEach(groups) { g in
                GroupHeader(project: g.project).padding(.top, 4)
                ForEach(g.tasks) { TaskRow(task: $0, compact: true) }
            }
        } else {
            let today = Queries.today(data, now: ui.now)
            if today.isEmpty {
                let upNext = Queries.grouped(Queries.upNext(data, now: ui.now), projects: data.projects)
                AllClear(hasUpNext: !upNext.isEmpty)
                ForEach(upNext) { g in
                    GroupHeader(project: g.project).padding(.top, 4)
                    ForEach(g.tasks) { TaskRow(task: $0, alwaysShowSun: true, compact: true) }
                }
            } else {
                ForEach(today) { TaskRow(task: $0, showProjectTag: true, compact: true) }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Open MeToDo", action: openMain)
                .buttonStyle(.borderless)
                .keyboardShortcut("o")
            Spacer()
            Menu {
                Toggle("Launch at Login", isOn: Binding(get: { LoginItem.isOn }, set: { LoginItem.set($0) }))
                Button("Open MeToDo", action: openMain)
                Divider()
                Button("Quit MeToDo") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func openMain() {
        openWindow(id: "main")
        NSApp.activate()
    }
}
```

- [ ] **Step 2: Menu bar icon with overdue dot**

Replace `Sources/MeToDo/MenuBarLabel.swift`:
```swift
import SwiftUI
import AppKit
import MeToDoCore

/// The menu bar icon. It's alive for the whole session, so it also opens the main
/// window on request (first launch, notification clicks, ⌘N).
struct MenuBarLabel: View {
    @Environment(Store.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: MenuBarIcon.image(overdue: Queries.anyOverdue(store.data, now: ui.now)))
            .onChange(of: ui.openMainWindowToken, initial: true) { _, token in
                guard token > 0 else { return }
                openWindow(id: "main")
                NSApp.activate()
            }
    }
}

enum MenuBarIcon {
    /// Template checkmark normally; with a red dot while anything is overdue (spec §5).
    static func image(overdue: Bool) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let symbol = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "MeToDo")!
            .withSymbolConfiguration(config)!
        guard overdue else {
            symbol.isTemplate = true
            return symbol
        }
        let size = symbol.size
        // The drawing handler runs at draw time with the menu bar's appearance, so labelColor
        // matches light/dark menu bars even though the image isn't a template.
        let image = NSImage(size: size, flipped: false) { rect in
            symbol.draw(in: rect)
            NSColor.labelColor.set()
            rect.fill(using: .sourceAtop)
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.maxX - 6, y: rect.maxY - 6, width: 6, height: 6)).fill()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "MeToDo, overdue tasks"
        return image
    }
}
```

- [ ] **Step 3: Build, install and check**

Run: `swift build && ./install.sh`

Manual check against `docs/superpowers/specs/mockups/menubar-popover.html`:
1. **Today state.** Clicking the icon shows the Today tab with a project tag on each row, sorted overdue → timed → ☀️ picks.
2. **Empty Today.** When Today is empty you see "All clear for today", then Up next grouped by project with ☀️ buttons. Clicking ☀️ moves the task into Today.
3. **Tabs.** The All tab shows the project groups. ⌘1 and ⌘2 switch tabs.
4. **Quick add.** The Add field is focused when the popover opens. In Today, a new task gets ☀️.
5. **Row actions.** Ticking, inline editing, expanding subtasks and the 🔔 picker all work in the popover.
6. **Footer.** ⌘O and ⤢ open the main window. ⚙︎ → Launch at Login toggles, and Quit MeToDo quits.
7. **Overdue dot.** Set a task's reminder 1 minute in the past (🔔 → custom time). Within 60s the icon shows a red dot. Check it in both light and dark menu bars. If the dot doesn't render, swap the overdue image for the template symbol `"exclamationmark.circle"` and note it in the commit.

- [ ] **Step 4: Commit**

```bash
git add Sources/MeToDo
git commit -m "feat(app): menu bar popover with Today/All, quick add and overdue dot" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Reminders (notifications, actions, self-heal)

**Files:**
- Create: `Sources/MeToDo/ReminderScheduler.swift`
- Modify: `Sources/MeToDo/AppDelegate.swift`
- Modify: `Sources/MeToDo/MeToDoApp.swift` (inject the scheduler)
- Modify: `Sources/MeToDo/PopoverView.swift` (the "Reminders are off · Fix…" row)

**Interfaces:**
- Consumes:
  - `Queries.reminderPlan`, `Queries.reminderDiff`, `PlannedReminder` (Task 3)
  - `Store.complete`, `Store.snooze`, `Store.task` (Task 5)
  - `UIState.showTask` (Task 6)
- Produces: `@MainActor @Observable final class ReminderScheduler: NSObject, UNUserNotificationCenterDelegate` with:
  - `init(store:ui:)`
  - `install()`, `start() async`, `resync()`, `refreshAuthorization() async`
  - `remindersOff: Bool`

- [ ] **Step 1: Scheduler**

`Sources/MeToDo/ReminderScheduler.swift`:
```swift
import AppKit
import UserNotifications
import MeToDoCore

/// Keeps macOS's pending notifications in sync with the store and handles the alert buttons (spec §8).
@MainActor @Observable
final class ReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    private(set) var remindersOff = false
    @ObservationIgnored private let store: Store
    @ObservationIgnored private let ui: UIState
    @ObservationIgnored private var scheduled: [UUID: PlannedReminder] = [:]
    @ObservationIgnored private let center = UNUserNotificationCenter.current()

    private enum Action {
        static let category = "TASK_REMINDER"
        static let complete = "COMPLETE"
        static let snooze10 = "SNOOZE_10"
        static let snooze60 = "SNOOZE_60"
        static let tomorrow = "TOMORROW"
    }

    init(store: Store, ui: UIState) {
        self.store = store
        self.ui = ui
        super.init()
    }

    /// Call from applicationWillFinishLaunching so an action that launched the app is delivered.
    func install() {
        center.delegate = self
        let actions = [
            UNNotificationAction(identifier: Action.complete, title: "Complete"),
            UNNotificationAction(identifier: Action.snooze10, title: "Snooze 10 min"),
            UNNotificationAction(identifier: Action.snooze60, title: "Snooze 1 hr"),
            UNNotificationAction(identifier: Action.tomorrow, title: "Tomorrow 9 AM"),
        ]
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Action.category, actions: actions, intentIdentifiers: []),
        ])
    }

    /// Ask permission, then self-heal: drop every pending request and rebuild from saved data.
    func start() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        await refreshAuthorization()
        center.removeAllPendingNotificationRequests()
        scheduled = [:]
        resync()
    }

    func refreshAuthorization() async {
        remindersOff = await center.notificationSettings().authorizationStatus == .denied
    }

    /// Cheap to call often: only changed requests are touched. Called on every store change and every minute.
    func resync() {
        let now = Date()
        let plan = Queries.reminderPlan(store.data, now: now)
        let diff = Queries.reminderDiff(scheduled: scheduled, plan: plan, now: now)
        if !diff.remove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: diff.remove.map(\.uuidString))
        }
        for r in diff.add { center.add(request(for: r)) }
        scheduled = Dictionary(plan.map { ($0.taskID, $0) }, uniquingKeysWith: { first, _ in first })
        clearDeliveredForClosedTasks()
    }

    private func request(for r: PlannedReminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = r.title
        content.subtitle = r.subtitle
        content.sound = .default
        content.categoryIdentifier = Action.category
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: r.date)
        return UNNotificationRequest(identifier: r.taskID.uuidString, content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
    }

    /// A persistent alert for a task you've since completed or deleted shouldn't linger.
    private func clearDeliveredForClosedTasks() {
        let openIDs = Set(store.data.tasks.filter { !$0.isDone }.map(\.id.uuidString))
        center.getDeliveredNotifications { notes in
            let stale = notes.map(\.request.identifier).filter { !openIDs.contains($0) }
            if !stale.isEmpty { UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: stale) }
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let id = UUID(uuidString: response.notification.request.identifier)
        Task { @MainActor in
            self.handle(action: action, taskID: id)
            completionHandler()
        }
    }

    private func handle(action: String, taskID: UUID?) {
        guard let taskID, store.task(taskID) != nil else { return }
        switch action {
        case Action.complete: store.complete(taskID)
        case Action.snooze10: store.snooze(taskID, .tenMinutes)
        case Action.snooze60: store.snooze(taskID, .oneHour)
        case Action.tomorrow: store.snooze(taskID, .tomorrowMorning)
        case UNNotificationDefaultActionIdentifier: ui.showTask(taskID)
        default: break
        }
    }
}
```

- [ ] **Step 2: Wire the scheduler into the app delegate**

Replace `Sources/MeToDo/AppDelegate.swift`:
```swift
import AppKit
import MeToDoCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store: Store
    let ui: UIState
    let reminders: ReminderScheduler
    /// One app-wide undo stack so ⌘Z works the same from the window and the popover.
    let undoManager = UndoManager()
    private var timer: Timer?

    override init() {
        store = Store(persistence: Persistence(url: Persistence.defaultURL))
        ui = UIState()
        reminders = ReminderScheduler(store: store, ui: ui)
        super.init()
        store.undoManager = undoManager
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        reminders.install()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !UserDefaults.standard.bool(forKey: "didFirstLaunch") {
            UserDefaults.standard.set(true, forKey: "didFirstLaunch")
            LoginItem.set(true)
            ui.openMainWindowToken += 1
        }
        if let issue = store.loadIssue {
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "MeToDo couldn't read its data"
            alert.informativeText = issue
            alert.runModal()
        }
        store.onChange = { [weak self] in self?.reminders.resync() }
        Task { await reminders.start() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }

    /// Rolls Today/overdue forward and schedules reminders that were beyond the 64 cap.
    private func tick() {
        ui.now = Date()
        reminders.resync()
    }
}
```

- [ ] **Step 3: Inject the scheduler and add the "Reminders are off" row**

In `Sources/MeToDo/MeToDoApp.swift`, add `.environment(appDelegate.reminders)` to `PopoverView()`. It goes after its existing two `.environment` lines.

In `Sources/MeToDo/PopoverView.swift`:
- Add `@Environment(ReminderScheduler.self) private var reminders` below the other `@Environment` properties.
- Insert the row directly above `if let error = store.saveError { WarningBanner(text: error) }`:
```swift
            if reminders.remindersOff {
                Button {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                } label: {
                    Label("Reminders are off · Fix…", systemImage: "bell.slash")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.orange)
                .padding(.horizontal, 12).padding(.vertical, 6)
            }
```
- Add `.task { await reminders.refreshAuthorization() }` after `.frame(width: 340, height: 440)`.

- [ ] **Step 4: Build, install and check (spec §8, §12 items 4–6)**

Run: `swift build && swift test && ./install.sh`

Manual check:
1. **Permission.** On first run macOS asks for notification permission. Allow it.
2. **Alert style.** In System Settings › Notifications › MeToDo, the style shows **Alerts**. If it shows Banners, the plist key wasn't honored. Note it and set Alerts by hand. The spec allows the user to change this.
3. **Fires while quit.** Add `Test alert in 2 minutes`, or set a 🔔 custom time 1–2 minutes out. Then quit MeToDo from ⚙︎ → Quit. The alert must still appear and stay on screen, with Complete / Snooze 10 min / Snooze 1 hr / Tomorrow 9 AM under "Options".
4. **Snooze.** Snooze 10 min launches the app if it's not running, and the task shows `🔔 Today <time+10m>` in Today.
5. **Complete.** Complete marks the task done.
6. **Click to open.** Clicking the alert body opens the main window with the task selected in All.
7. **Cleanup.** Completing a task in-app removes its lingering alert from Notification Center.
8. **Permission denied.** Turn notifications off for MeToDo in System Settings and reopen the popover. "Reminders are off · Fix…" appears and opens that settings page.

- [ ] **Step 5: Commit**

```bash
git add Sources/MeToDo
git commit -m "feat(app): persistent reminders with snooze/complete actions and self-healing schedule" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: README and end-to-end verification

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: the finished app.
- Produces: user-facing install notes and a verified build.

- [ ] **Step 1: README**

`README.md`:
````markdown
# MeToDo

A minimal macOS to-do app that lives in your menu bar.

## Install / update

```bash
./install.sh
```

Builds the app, installs it to `/Applications/MeToDo.app` and launches it. Re-run after any change; your tasks are kept.

## Where your data lives

`~/Library/Application Support/MeToDo/data.json`, plus `data.json.bak`, which is the copy from the last successful launch. Copy that folder to back up.

## Uninstall

Quit from the menu bar ⚙︎ menu, then delete `/Applications/MeToDo.app` (and the data folder above if you want).

## Develop

`swift test` runs the core tests. Don't use `swift run`: notifications need the app bundle, so use `./install.sh`.
````

- [ ] **Step 2: Run the full automated suite**

Run: `swift test`
Expected: all suites pass with 0 failures.

- [ ] **Step 3: Run the spec §12 manual checklist on a fresh install**

Run: `defaults delete com.josearci.metodo didFirstLaunch; ./install.sh`

1. From the popover, add `Plan sprint #sprint tomorrow 9am` (create Sprint first). It lands in Sprint with `🔔 Tomorrow 9:00 AM`.
2. Add 3 subtasks and tick 1. `◔ 1/3` shows in both the window and the popover.
3. ☀️ a task. Check the Today order, then complete everything to see "All clear for today" and Up next.
4. Set a reminder 1 minute out and quit the app. The alert fires and stays on screen.
5. Snooze it from the alert. The new time shows in Today.
6. Complete a task from an alert.
7. Log out and back in. The menu bar icon returns.
8. Check light and dark mode against both mockups.

Record anything that fails as a bug, and fix it with superpowers:systematic-debugging before continuing.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: install, data location and dev notes" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
