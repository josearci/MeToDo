import SwiftUI
import MeToDoCore

/// One task, shared by the main window and the popover (spec §4, §5).
struct TaskRow: View {
    @Environment(Store.self) private var store
    @Environment(UIState.self) private var ui
    let task: TaskItem
    /// Popover's Today list shows the project as a small tag instead of group headers.
    var showProjectTag = false
    /// Up next always shows ☀️ so a task can be pulled into Today.
    var alwaysShowSun = false
    var compact = false

    @State private var hovering = false
    @State private var editing = false
    @State private var draft = ""
    @State private var pendingDone = false
    @State private var doneGeneration = 0
    @State private var showReminder = false
    @FocusState private var titleFocused: Bool

    private var project: Project? { store.project(task.projectID) }
    private var color: ProjectTint { project?.tint ?? ProjectColor.gray.tint }
    private var isExpanded: Bool { ui.expanded.contains(task.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 10) {
                CheckBox(isOn: task.isDone || pendingDone, color: color.color, size: compact ? 13 : 14, action: toggleDone)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    title
                    meta
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !task.isDone && (hovering || alwaysShowSun) { actions }
            }
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        ChipMenu(icon: "flag", text: task.priority == .none ? "Priority" : task.priority.label,
                                 tint: task.priority == .none ? .secondary : task.priority.color) {
                            PriorityMenuItems(selection: task.priority) { store.setPriority(task.id, $0) }
                        }
                        .help("Priority")
                        ChipMenu(icon: "clock", text: task.estimate.map(Queries.durationLabel) ?? "Estimate", tint: .secondary) {
                            EstimateMenuItems(minutes: task.estimate) { store.setEstimate(task.id, $0) }
                        }
                        .help("How long it should take")
                    }
                    NotesEditor(task: task)
                    SubtaskList(task: task, color: color)
                }
                .padding(.leading, 24)
                .padding(.top, 4)
            }
        }
        .font(.system(size: compact ? 12.5 : 13))
        .padding(.vertical, compact ? 4 : 5)
        .opacity(pendingDone ? 0.4 : task.isDone ? 0.6 : 1)
        .animation(.easeOut(duration: 0.2), value: pendingDone)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .popover(isPresented: $showReminder, arrowEdge: .trailing) {
            ReminderPicker(current: task.remindAt) { store.setReminder(task.id, $0) }
        }
        .onChange(of: ui.editingTaskID) { _, id in
            guard id == task.id else { return }
            ui.editingTaskID = nil
            beginEditing()
        }
        .contextMenu { contextMenu }
    }

    @ViewBuilder private var title: some View {
        if editing {
            TextField("Task", text: $draft)
                .textFieldStyle(.plain)
                .focused($titleFocused)
                .onSubmit(commitEdit)
                .onExitCommand { editing = false }
                .onChange(of: titleFocused) { _, focused in if !focused { commitEdit() } }
        } else {
            // Clicking the title line expands the task (notes + subtasks). Rename: right-click → Rename, or Return.
            // A Button (not a tap gesture) so the click is never held back or swallowed by the list.
            Button { ui.toggleExpanded(task.id) } label: {
                Text(task.title)
                    .foregroundStyle(task.isDone ? AnyShapeStyle(.secondary) : AnyShapeStyle(color.titleColor))
                    .strikethrough(task.isDone)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Hide notes" : "Show notes and subtasks")
        }
    }

    @ViewBuilder private var meta: some View {
        let progress = task.subtaskProgress
        let tag = showProjectTag ? project : nil
        let hasNotes = !task.notes.isEmpty && !isExpanded
        let minutes = task.isDone ? nil : Queries.minutesLeft(task)
        let flagged = task.priority != .none && !task.isDone
        if progress.total > 0 || task.remindAt != nil || task.inToday || tag != nil || hasNotes || flagged || minutes != nil {
            HStack(spacing: 10) {
                if flagged {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(task.priority.color)
                        .help("\(task.priority.label) priority")
                }
                if progress.total > 0 {
                    Button { ui.toggleExpanded(task.id) } label: {
                        HStack(spacing: 4) {
                            ProgressRing(fraction: Double(progress.done) / Double(progress.total), color: color.color)
                            Text("\(progress.done)/\(progress.total)")
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(color.color)
                }
                if let remindAt = task.remindAt {
                    Label(Queries.reminderLabel(remindAt, now: ui.now), systemImage: "bell")
                        .foregroundStyle(Queries.isOverdue(task, now: ui.now) ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                }
                if let minutes {
                    Label(Queries.durationLabel(minutes), systemImage: "clock")
                        .help(task.subtasks.contains { $0.estimate != nil } ? "Estimated time left in open subtasks" : "Estimate")
                }
                if hasNotes {
                    Image(systemName: "note.text").help("Has notes")
                }
                if task.inToday && tag == nil {
                    Image(systemName: "sun.max.fill").foregroundStyle(.yellow)
                }
                if let tag {
                    Text(tag.displayName).foregroundStyle(color.color)
                }
            }
            .font(.system(size: compact ? 10.5 : 11))
            .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button { store.toggleToday(task.id) } label: {
                Image(systemName: task.inToday ? "sun.max.fill" : "sun.max")
            }
            .foregroundStyle(task.inToday ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
            .help(task.inToday ? "Remove from Today (⌘T)" : "Add to Today (⌘T)")
            if hovering {
                ProjectMenu(selected: task.projectID, onPick: { store.move(task.id, toProject: $0.id) }) {
                    Image(systemName: "folder")
                }
                .foregroundStyle(.secondary)
                .help("Move to project")
                Button { showReminder = true } label: {
                    Image(systemName: task.remindAt == nil ? "bell" : "bell.fill")
                }
                .foregroundStyle(.secondary)
                .help("Reminder")
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var contextMenu: some View {
        Button("Rename") { beginEditing() }
        Button(task.inToday ? "Remove from Today" : "Add to Today") { store.toggleToday(task.id) }
        Button("Add Subtask") { ui.expanded.insert(task.id) }
        Button("Set Reminder…") { showReminder = true }
        Menu("Priority") { PriorityMenuItems(selection: task.priority) { store.setPriority(task.id, $0) } }
        Menu("Estimate") { EstimateMenuItems(minutes: task.estimate) { store.setEstimate(task.id, $0) } }
        Menu("Move to") {
            ForEach(store.data.projects) { p in
                Button { store.move(task.id, toProject: p.id) } label: { ProjectMenuLabel(project: p) }
                    .disabled(p.id == task.projectID)
            }
        }
        Divider()
        Button("Delete", role: .destructive) { store.delete(task.id) }
    }

    private func beginEditing() {
        guard !task.isDone else { return }
        draft = task.title
        editing = true
        DispatchQueue.main.async { titleFocused = true }
    }

    private func commitEdit() {
        guard editing else { return }
        editing = false
        store.rename(task.id, to: draft)
    }

    /// Ticking fades the row for ~1s before it moves to Done; clicking again cancels (spec §4).
    private func toggleDone() {
        if task.isDone { store.toggleDone(task.id); return }
        doneGeneration += 1
        if pendingDone { pendingDone = false; return }
        pendingDone = true
        let generation = doneGeneration
        Task {
            try? await Task.sleep(for: .seconds(1))
            guard pendingDone, generation == doneGeneration else { return }
            pendingDone = false
            store.complete(task.id)   // idempotent: it may have been completed elsewhere meanwhile
        }
    }
}
