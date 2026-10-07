import AppKit
import MeToDoCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store: Store
    let ui: UIState
    let reminders: ReminderScheduler
    let updater = Updater()
    /// One app-wide undo stack so ⌘Z works the same from the window and the popover.
    let undoManager = UndoManager()
    private var timer: Timer?
    private var statusItem: StatusItemController?

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
        DebugProbe.install(store: store, ui: ui, reminders: reminders)
        #endif
        let status = StatusItemController(store: store, ui: ui, reminders: reminders, updater: updater)
        statusItem = status
        ui.openMainWindow = { [weak self] in self?.openMainWindow() }
        if !UserDefaults.standard.bool(forKey: "didFirstLaunch") {
            UserDefaults.standard.set(true, forKey: "didFirstLaunch")
            LoginItem.set(true)
            ui.openMainWindow()
        }
        if let issue = store.loadIssue {
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "MeToDo couldn't read its data"
            alert.informativeText = issue
            alert.runModal()
        }
        store.onChange = { [weak self] in
            self?.reminders.resync()
            self?.statusItem?.refreshIcon()
        }
        Task { await reminders.start() }
        updater.start()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    /// Closes the menu bar popover and shows the main window.
    func openMainWindow() {
        statusItem?.close()
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }), window.isVisible {
            window.makeKeyAndOrderFront(nil)
        } else if let open = ui.openWindowAction {
            open(id: "main")
        } else {
            ui.pendingOpenMain = true   // OpenWindowRelay opens it as soon as it appears
        }
    }

    /// A menu bar app keeps running with no windows open.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }

    /// Rolls Today/overdue forward and schedules reminders that were beyond the 64 cap.
    private func tick() {
        ui.now = Date()
        reminders.resync()
        statusItem?.refreshIcon()
        Task { await reminders.refreshAuthorization() }
    }
}
