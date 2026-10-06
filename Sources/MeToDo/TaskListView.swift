import SwiftUI
import MeToDoCore

struct TaskListView: View {
    @Environment(Store.self) private var store
    @Environment(UIState.self) private var ui
    @State private var showDone = false

    var body: some View {
        @Bindable var ui = ui
        let data = store.data
        VStack(spacing: 0) {
            List(selection: $ui.selectedTaskID) {
                switch ui.sidebar {
                case .today:
                    let today = Queries.today(data, now: ui.now)
                    if today.isEmpty {
                        let upNext = Queries.upNext(data, now: ui.now)
                        AllClear(hasUpNext: !upNext.isEmpty).listRowSeparator(.hidden)
                        groups(upNext, movable: false, alwaysShowSun: true)
                    } else {
                        ForEach(today) { TaskRow(task: $0, showProjectTag: true).listRowSeparator(.hidden) }
                    }
                case .all:
                    groups(Queries.open(data), movable: true)
                case .project(let id):
                    groups(Queries.open(data, project: id), movable: true)
                }
                doneSection(doneTasks(data))
            }
            .listStyle(.plain)
            .onKeyPress(.space) { act { store.toggleDone($0) } }
            .onKeyPress(.return) { act { ui.editingTaskID = $0 } }
            .onKeyPress(.delete) { act { store.delete($0); ui.selectedTaskID = nil } }
            .onKeyPress(.rightArrow) { act { ui.expanded.insert($0) } }
            .onKeyPress(.leftArrow) { act { ui.expanded.remove($0) } }

            AddField(placement: .window)
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)
        }
        .navigationTitle(title)
        .navigationSubtitle("\(openCount) open")
    }

    /// Projects in order, each with its header and color rail. Drag to reorder inside a project;
    /// drag onto a sidebar project to move it there.
    @ViewBuilder private func groups(_ tasks: [TaskItem], movable: Bool, alwaysShowSun: Bool = false) -> some View {
        ForEach(Queries.grouped(tasks, projects: store.data.projects)) { g in
            Section {
                ForEach(g.tasks) { t in
                    TaskRow(task: t, alwaysShowSun: alwaysShowSun)
                        .rail(g.project.color)
                        .itemProvider { NSItemProvider(object: t.id.uuidString as NSString) }
                }
                .onMove(perform: movable ? { (from: IndexSet, to: Int) in
                    store.moveTasks(g.tasks.map(\.id), fromOffsets: from, toOffset: to)
                } : nil)
            } header: {
                GroupHeader(project: g.project).rail(g.project.color)
            }
        }
    }

    @ViewBuilder private func doneSection(_ done: [TaskItem]) -> some View {
        if !done.isEmpty {
            Section {
                if showDone {
                    ForEach(done) { TaskRow(task: $0).listRowSeparator(.hidden) }
                }
            } header: {
                HStack {
                    Button { showDone.toggle() } label: {
                        Label("Done · \(done.count)", systemImage: showDone ? "chevron.down" : "chevron.right")
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    if showDone {
                        Button("Clear") { store.clearDone(done.map(\.id)) }.buttonStyle(.borderless)
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 10)
            }
        }
    }

    private func doneTasks(_ data: AppData) -> [TaskItem] {
        switch ui.sidebar {
        case .today:
            Queries.done(data).filter { $0.completedAt.map { Calendar.current.isDate($0, inSameDayAs: ui.now) } ?? false }
        case .all:
            Queries.done(data)
        case .project(let id):
            Queries.done(data, project: id)
        }
    }

    private var title: String {
        switch ui.sidebar {
        case .today: "Today"
        case .all: "All"
        case .project(let id): store.project(id)?.displayName ?? "Project"
        }
    }

    private var openCount: Int {
        switch ui.sidebar {
        case .today: Queries.today(store.data, now: ui.now).count
        case .all: Queries.open(store.data).count
        case .project(let id): Queries.openCount(store.data, project: id)
        }
    }

    private func act(_ f: (UUID) -> Void) -> KeyPress.Result {
        // Keys typed into a title or subtask field belong to that field, not the list.
        guard let id = ui.selectedTaskID, !(NSApp.keyWindow?.firstResponder is NSTextView) else { return .ignored }
        f(id)
        return .handled
    }
}
