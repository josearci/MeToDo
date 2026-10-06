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
        #if DEBUG
        store = Store(persistence: Persistence(url: DebugProbe.dataURL ?? Persistence.defaultURL))
        #else
        store = Store(persistence: Persistence(url: Persistence.defaultURL))
        #endif
        ui = UIState()
        reminders = ReminderScheduler(store: store, ui: ui)
        super.init()
        store.undoManager = undoManager
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        reminders.install()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        DebugProbe.install(store: store, ui: ui)
        #endif
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
        Task { await reminders.refreshAuthorization() }
    }
}
