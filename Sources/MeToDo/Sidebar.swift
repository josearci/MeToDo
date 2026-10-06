import SwiftUI
import MeToDoCore

/// Today, All, then projects (spec §4). Projects reorder by drag and accept dropped tasks.
struct Sidebar: View {
    @Environment(Store.self) private var store
    @Environment(UIState.self) private var ui
    @State private var editing: Project?
    @State private var creating = false
    @State private var deleting: Project?
    /// Dragged narrow enough that only icons fit: show big emoji/icons instead of names.
    @State private var compact = false

    var body: some View {
        let data = store.data
        List(selection: Binding<SidebarItem?>(get: { ui.sidebar }, set: { if let v = $0 { ui.sidebar = v } })) {
            row("Today", count: Queries.today(data, now: ui.now).count) {
                Image(systemName: "sun.max.fill").foregroundStyle(.yellow)
            } big: {
                Image(systemName: "sun.max.fill").font(.system(size: 20)).foregroundStyle(.yellow)
            }
            .tag(SidebarItem.today)
            row("All", count: Queries.open(data).count) {
                Image(systemName: "tray.full").foregroundStyle(.secondary)
            } big: {
                Image(systemName: "tray.full").font(.system(size: 18)).foregroundStyle(.secondary)
            }
            .tag(SidebarItem.all)
            Section {
                ForEach(data.projects) { p in
                    row(p.displayName, count: Queries.openCount(data, project: p.id)) {
                        Circle().fill(p.color.color).frame(width: 8, height: 8)
                    } big: {
                        BigProjectIcon(project: p)
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
            } header: {
                if !compact { Text("Projects") }
            }
        }
        .onGeometryChange(for: Bool.self, of: { $0.size.width < 120 }) { compact = $0 }
        .safeAreaInset(edge: .bottom) {
            Button { creating = true } label: {
                if compact { Image(systemName: "plus").font(.system(size: 16)) } else { Label("New Project", systemImage: "plus") }
            }
            .buttonStyle(.borderless)
            .help("New Project")
            .padding(12)
            .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
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

    @ViewBuilder
    private func row(_ title: String, count: Int, @ViewBuilder icon: () -> some View, @ViewBuilder big: () -> some View) -> some View {
        if compact {
            // Icon-only: bigger, centered, easy to click; name on hover, count as a small badge.
            big()
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        Text("\(count)")
                            .font(.system(size: 9, weight: .semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.3), in: Capsule())
                    }
                }
                .help(count > 0 ? "\(title) · \(count) open" : title)
        } else {
            HStack(spacing: 8) {
                icon().frame(width: 16)
                Text(title).lineLimit(1)
                Spacer()
                if count > 0 { Text("\(count)").foregroundStyle(.secondary).monospacedDigit() }
            }
        }
    }
}

/// A project's emoji, large; projects without one get a colored circle with their initial.
private struct BigProjectIcon: View {
    let project: Project

    var body: some View {
        if let emoji = project.emoji, !emoji.isEmpty {
            Text(emoji).font(.system(size: 22))
        } else {
            Circle()
                .fill(project.color.color)
                .frame(width: 24, height: 24)
                .overlay {
                    Text(project.name.prefix(1).uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
        }
    }
}
