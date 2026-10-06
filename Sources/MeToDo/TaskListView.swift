import SwiftUI
import MeToDoCore

struct TaskListView: View {
    @Environment(Store.self) private var store
    @Environment(UIState.self) private var ui

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
                    let open = Queries.open(data)
                    if open.isEmpty { emptyState }
                    groups(open, movable: true)
                case .project(let id):
                    let open = Queries.open(data, project: id)
                    if open.isEmpty { emptyState }
                    groups(open, movable: true)
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
                // The header is a row (not a Section header) so it lines up with the tasks; the bar is on tasks only..
                GroupHeader(project: g.project).rail(g.project.color, bar: false).selectionDisabled()
                ForEach(g.tasks) { t in
                    TaskRow(task: t, alwaysShowSun: alwaysShowSun)
                        .rail(g.project.color)
                        .itemProvider { NSItemProvider(object: t.id.uuidString as NSString) }
                }
                .onMove(perform: movable ? { (from: IndexSet, to: Int) in
                    store.moveTasks(g.tasks.map(\.id), fromOffsets: from, toOffset: to)
                } : nil)
            }
        }
    }

    private var emptyState: some View {
        Text("No open tasks · add one below")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
            .listRowSeparator(.hidden)
            .selectionDisabled()
    }

    @ViewBuilder private func doneSection(_ done: [TaskItem]) -> some View {
        if !done.isEmpty {
            Section {
                DoneHeader(count: done.count) { store.clearDone(done.map(\.id)) }
                    .listRowSeparator(.hidden)
                    .selectionDisabled()
                ForEach(done) { TaskRow(task: $0).listRowSeparator(.hidden) }
            }
        }
    }

    private func doneTasks(_ data: AppData) -> [TaskItem] {
        switch ui.sidebar {
        case .today:
            Queries.doneToday(data, now: ui.now)
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
