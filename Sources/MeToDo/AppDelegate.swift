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
    /// Held for the app's lifetime so `metodo` never writes data.json under us (see AppLink).
    private let dataLock: Int32?
    private var cliPort: CFMessagePort?

    override init() {
        let persistence = Persistence(url: Persistence.defaultURL)
        let link = AppLink(persistence: persistence)
        // Taken before loading, so a `metodo` mid-write finishes first. ponytail: gives up after 10 s
        // (another copy of the app has it); two copies at once already overwrote each other before the CLI.
        dataLock = link.lock(timeout: 10)
        store = Store(persistence: persistence)
        ui = UIState()
        reminders = ReminderScheduler(store: store, ui: ui)
        super.init()
        store.undoManager = undoManager
        cliPort = link.serve { [store] args in Self.runCLI(store) { CLI.run(args, store: store) } }
    }

    /// Runs a `metodo` command or metodo:// link on the live store and saves before answering,
    /// so the change is on disk by the time the CLI prints it.
    private static func runCLI(_ store: Store, _ command: () -> CLI.Output) -> CLI.Output {
        let before = store.data
        let output = command()
        if store.data != before { store.saveNow() }
        return output
    }

    /// metodo://add?title=…, metodo://complete?id=… (see CLI.run(url:store:)).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            let output = Self.runCLI(store) { CLI.run(url: url, store: store) }
            guard output.status != 0 else { continue }
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "MeToDo couldn't open that link"
            alert.informativeText = output.err.replacingOccurrences(of: "metodo: ", with: "")
            alert.runModal()
        }
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
        }
        // Opened by hand (installer, Finder, Spotlight) → show the window; the menu bar icon may be
        // hidden by the notch or System Settings › Menu Bar. Started at login → stay in the menu bar.
        if !LoginItem.launchedAtLogin {
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

    /// Opening MeToDo while it's already running (Finder, Spotlight, Launchpad) shows the window;
    /// with no Dock icon, nothing else would happen.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openMainWindow()
        return false
    }

    /// A menu bar app keeps running with no windows open.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        if let cliPort { CFMessagePortInvalidate(cliPort) }   // metodo now waits for the lock instead
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
