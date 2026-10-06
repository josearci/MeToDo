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
