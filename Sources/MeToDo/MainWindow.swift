import SwiftUI
import MeToDoCore

/// Interim: grouped All list + Add field, so Task 7's components can be checked. Replaced in Task 8.
struct MainWindow: View {
    @Environment(Store.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(Queries.grouped(Queries.open(store.data), projects: store.data.projects)) { g in
                    Section {
                        ForEach(g.tasks) { TaskRow(task: $0).rail(g.project.color) }
                    } header: {
                        GroupHeader(project: g.project).rail(g.project.color)
                    }
                }
            }
            .listStyle(.plain)
            AddField(defaultProjectID: nil, inToday: false).padding(16)
        }
        .frame(minWidth: 640, minHeight: 420)
        .onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate() }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }
}
