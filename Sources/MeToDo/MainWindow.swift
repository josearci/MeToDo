import SwiftUI
import MeToDoCore

struct MainWindow: View {
    @Environment(Store.self) private var store

    var body: some View {
        NavigationSplitView {
            Sidebar().navigationSplitViewColumnWidth(min: 66, ideal: 200, max: 280)
        } detail: {
            TaskListView()
        }
        .frame(minWidth: 640, minHeight: 420)
        // No green zoom button: close + minimize fit the icon-only sidebar. Full screen stays in View (⌃⌘F).
        .background(WindowReader { $0?.standardWindowButton(.zoomButton)?.isHidden = true })
        .overlay(alignment: .bottom) {
            if let error = store.saveError { WarningBanner(text: error).padding(.bottom, 60) }
        }
        // Dock icon only while the window is open (spec §9).
        .onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate() }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }
}
