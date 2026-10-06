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
