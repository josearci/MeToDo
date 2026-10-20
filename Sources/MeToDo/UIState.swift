import Foundation
import SwiftUI
import Observation

enum SidebarItem: Hashable {
    case today, all, completed
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
    /// Opens (or focuses) the main window; set by AppDelegate.
    @ObservationIgnored var openMainWindow: () -> Void = {}
    /// SwiftUI's open-window action, handed over by a tiny view living in the menu bar icon.
    @ObservationIgnored var openWindowAction: OpenWindowAction?
    /// The main window was requested before that action arrived (first launch).
    @ObservationIgnored var pendingOpenMain = false
    /// Bumped to focus the main window's Add field (⌘N).
    var focusAddFieldToken = 0

    /// Notification click: show the task in the main window.
    func showTask(_ id: UUID) {
        sidebar = .all
        selectedTaskID = id
        openMainWindow()
    }

    func toggleExpanded(_ id: UUID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }
}
