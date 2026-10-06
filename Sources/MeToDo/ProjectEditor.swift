import SwiftUI
import MeToDoCore

/// Create or edit a project: name, one of 8 colors, optional emoji.
struct ProjectEditor: View {
    @Environment(Store.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(\.dismiss) private var dismiss
    let original: Project?
    @State private var name: String
    @State private var emoji: String
    @State private var color: ProjectColor

    init(project: Project?) {
        original = project
        _name = State(initialValue: project?.name ?? "")
        _emoji = State(initialValue: project?.emoji ?? "")
        _color = State(initialValue: project?.color ?? .blue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(original == nil ? "New Project" : "Edit Project").font(.headline)
            TextField("Name", text: $name)
            HStack {
                TextField("Emoji (optional)", text: $emoji).frame(width: 140)
                Button("Pick…") { NSApp.orderFrontCharacterPalette(nil) }.buttonStyle(.borderless)
            }
            HStack(spacing: 10) {
                ForEach(ProjectColor.allCases, id: \.self) { c in
                    Circle().fill(c.color).frame(width: 20, height: 20)
                        .overlay(Circle().strokeBorder(.primary, lineWidth: c == color ? 2 : 0).padding(-4))
                        .onTapGesture { color = c }
                        .accessibilityLabel(c.rawValue.capitalized)
                        .accessibilityAddTraits(c == color ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(original == nil ? "Create" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func save() {
        if var p = original {
            p.name = name
            p.emoji = emoji
            p.color = color
            store.updateProject(p)
        } else if let p = store.addProject(name: name, color: color, emoji: emoji) {
            ui.sidebar = .project(p.id)
        }
        dismiss()
    }
}
