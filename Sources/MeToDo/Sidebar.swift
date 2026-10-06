import SwiftUI
import MeToDoCore

/// Today, All, then projects (spec §4). Projects reorder by drag and accept dropped tasks.
struct Sidebar: View {
    @Environment(Store.self) private var store
    @Environment(UIState.self) private var ui
    @State private var editing: Project?
    @State private var creating = false
    @State private var deleting: Project?

    var body: some View {
        let data = store.data
        List(selection: Binding<SidebarItem?>(get: { ui.sidebar }, set: { if let v = $0 { ui.sidebar = v } })) {
            row("Today", count: Queries.today(data, now: ui.now).count) {
                Image(systemName: "sun.max.fill").foregroundStyle(.yellow)
            }
            .tag(SidebarItem.today)
            row("All", count: Queries.open(data).count) {
                Image(systemName: "tray.full").foregroundStyle(.secondary)
            }
            .tag(SidebarItem.all)
            Section("Projects") {
                ForEach(data.projects) { p in
                    row(p.displayName, count: Queries.openCount(data, project: p.id)) {
                        Circle().fill(p.color.color).frame(width: 8, height: 8)
                    }
                    .tag(SidebarItem.project(p.id))
                    .contextMenu {
                        Button("Edit…") { editing = p }
                        if !p.isInbox { Button("Delete…", role: .destructive) { deleting = p } }
                    }
                    .dropDestination(for: String.self) { ids, _ in
                        let moved = ids.compactMap(UUID.init(uuidString:))
                        moved.forEach { store.move($0, toProject: p.id) }
                        return !moved.isEmpty
                    }
                }
                .onMove { store.moveProjects(fromOffsets: $0, toOffset: $1) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button { creating = true } label: { Label("New Project", systemImage: "plus") }
                .buttonStyle(.borderless)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $editing) { ProjectEditor(project: $0) }
        .sheet(isPresented: $creating) { ProjectEditor(project: nil) }
        .confirmationDialog("Delete \(deleting?.displayName ?? "")?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            presenting: deleting) { p in
            Button("Delete Project and Its Tasks", role: .destructive) {
                if ui.sidebar == .project(p.id) { ui.sidebar = .all }
                store.deleteProject(p.id)
            }
        } message: { p in
            Text("This also deletes its \(Queries.openCount(store.data, project: p.id)) open task(s). You can undo with ⌘Z.")
        }
    }

    private func row(_ title: String, count: Int, @ViewBuilder icon: () -> some View) -> some View {
        HStack(spacing: 8) {
            icon().frame(width: 16)
            Text(title).lineLimit(1)
            Spacer()
            if count > 0 { Text("\(count)").foregroundStyle(.secondary).monospacedDigit() }
        }
    }
}
