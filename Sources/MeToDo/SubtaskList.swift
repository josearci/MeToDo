import SwiftUI
import MeToDoCore

/// Indented subtasks plus an "Add subtask" field. Return adds one and keeps focus for the next.
struct SubtaskList: View {
    @Environment(Store.self) private var store
    let task: TaskItem
    let color: ProjectTint
    @State private var newTitle = ""
    @FocusState private var addFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(task.subtasks) { SubtaskRow(taskID: task.id, subtask: $0, color: color) }
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 9)).frame(width: 12)
                TextField("Add subtask", text: $newTitle)
                    .textFieldStyle(.plain)
                    .focused($addFocused)
                    .onSubmit {
                        if store.addSubtask(task.id, title: newTitle) != nil { newTitle = "" }
                        addFocused = true
                    }
            }
            .foregroundStyle(.tertiary)
        }
        .font(.system(size: 12.5))
        .padding(.vertical, 2)
    }
}

private struct SubtaskRow: View {
    @Environment(Store.self) private var store
    @Environment(UIState.self) private var ui
    let taskID: UUID
    let subtask: Subtask
    let color: ProjectTint
    @State private var editing = false
    @State private var showDue = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            CheckBox(isOn: subtask.isDone, color: color.color, size: 12) { store.toggleSubtask(taskID, subtask.id) }
            if editing {
                TextField("Subtask", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($fieldFocused)
                    .onSubmit(commit)
                    .onExitCommand { editing = false }
                    .onChange(of: fieldFocused) { _, focused in if !focused { commit() } }
            } else {
                Text(subtask.title)
                    .strikethrough(subtask.isDone)
                    .foregroundStyle(subtask.isDone ? .secondary : .primary)
                    .onTapGesture {
                        draft = subtask.title
                        editing = true
                        DispatchQueue.main.async { fieldFocused = true }
                    }
            }
            details
        }
        .popover(isPresented: $showDue, arrowEdge: .trailing) {
            ReminderPicker(current: subtask.dueAt, title: "Due") { store.setSubtaskDue(taskID, subtask.id, $0) }
        }
        .contextMenu {
            Button(subtask.dueAt == nil ? "Set Due…" : "Change Due…") { showDue = true }
            if subtask.dueAt != nil { Button("Remove Due") { store.setSubtaskDue(taskID, subtask.id, nil) } }
            Menu("Estimate") { EstimateMenuItems(minutes: subtask.estimate) { store.setSubtaskEstimate(taskID, subtask.id, $0) } }
            Divider()
            Button("Delete Subtask", role: .destructive) { store.deleteSubtask(taskID, subtask.id) }
        }
    }

    /// Due time (red once it passes) and estimate, after the title. Right-click to change them.
    @ViewBuilder private var details: some View {
        if subtask.dueAt != nil || subtask.estimate != nil {
            HStack(spacing: 8) {
                if let due = subtask.dueAt {
                    Label(Queries.reminderLabel(due, now: ui.now), systemImage: "calendar")
                        .foregroundStyle(!subtask.isDone && due <= ui.now ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                }
                if let m = subtask.estimate { Label(Queries.durationLabel(m), systemImage: "clock") }
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .onTapGesture { showDue = true }
        }
    }

    /// Clearing the text deletes the subtask.
    private func commit() {
        guard editing else { return }
        if draft.trimmingCharacters(in: .whitespaces).isEmpty {
            store.deleteSubtask(taskID, subtask.id)
        } else {
            store.renameSubtask(taskID, subtask.id, to: draft)
        }
        editing = false
    }
}
