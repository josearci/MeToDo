import SwiftUI
import MeToDoCore

/// Indented subtasks plus an "Add subtask" field. Return adds one and keeps focus for the next.
struct SubtaskList: View {
    @Environment(Store.self) private var store
    let task: TaskItem
    let color: ProjectColor
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
        .onAppear { if task.subtasks.isEmpty { addFocused = true } }
    }
}

private struct SubtaskRow: View {
    @Environment(Store.self) private var store
    let taskID: UUID
    let subtask: Subtask
    let color: ProjectColor
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        HStack(spacing: 8) {
            CheckBox(isOn: subtask.isDone, color: color.color, size: 12) { store.toggleSubtask(taskID, subtask.id) }
            if editing {
                TextField("Subtask", text: $draft)
                    .textFieldStyle(.plain)
                    .onSubmit(commit)
                    .onExitCommand { editing = false }
            } else {
                Text(subtask.title)
                    .strikethrough(subtask.isDone)
                    .foregroundStyle(subtask.isDone ? .secondary : .primary)
                    .onTapGesture { draft = subtask.title; editing = true }
            }
        }
        .contextMenu {
            Button("Delete Subtask", role: .destructive) { store.deleteSubtask(taskID, subtask.id) }
        }
    }

    /// Clearing the text deletes the subtask.
    private func commit() {
        if draft.trimmingCharacters(in: .whitespaces).isEmpty {
            store.deleteSubtask(taskID, subtask.id)
        } else {
            store.renameSubtask(taskID, subtask.id, to: draft)
        }
        editing = false
    }
}
