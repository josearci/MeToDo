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
