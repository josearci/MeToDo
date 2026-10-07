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
        .commands { AppCommands(store: appDelegate.store, ui: appDelegate.ui, undoManager: appDelegate.undoManager) }
        // The menu bar icon + popover live in StatusItemController (AppKit) so a hotkey can open them.
    }
}
