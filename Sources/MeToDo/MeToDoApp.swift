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
