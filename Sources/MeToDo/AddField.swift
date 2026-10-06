import SwiftUI
import MeToDoCore

/// "Add task" input. Understands `#project` and dates via Store.quickAdd (spec §7).
struct AddField: View {
    @Environment(Store.self) private var store
    @Environment(UIState.self) private var ui
    enum Placement { case window, popover }
    let placement: Placement
    var autofocus = false
    @State private var text = ""
    /// Project picked from the chip; nil means "the view's default" (current project, else Inbox).
    @State private var pickedProjectID: UUID?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !suggestions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(suggestions.prefix(6)) { p in
                        Button(p.displayName) { complete(with: p) }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(p.color.color)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(p.color.color.opacity(0.12), in: Capsule())
                    }
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "plus").foregroundStyle(.secondary)
                TextField("Add task", text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(submit)
                    .onKeyPress(.tab) {
                        guard let first = suggestions.first else { return .ignored }
                        complete(with: first)
                        return .handled
                    }
                if text.isEmpty {
                    Text("tomorrow 9am").font(.caption).foregroundStyle(.tertiary)
                }
                if let target = targetProject {
                    ProjectMenu(selected: target.id, onPick: { pickedProjectID = $0.id }) {
                        ProjectChip(project: target)
                    }
                    .help("Choose the project for new tasks")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
        }
        .onChange(of: ui.focusAddFieldToken) { focused = true }
        .onChange(of: ui.sidebar) { pickedProjectID = nil }
        .onAppear { if autofocus { focused = true } }
    }

    /// Defaults come from live UI state, not stored properties: the TextField keeps the submit
    /// action from an earlier render, so stored values would be one view behind.
    private var defaultProjectID: UUID? {
        if placement == .window, case .project(let id) = ui.sidebar { return id }
        return nil
    }

    /// New tasks added while looking at Today are pulled into Today.
    private var inToday: Bool {
        placement == .window ? ui.sidebar == .today : !ui.popoverShowsAll
    }

    private var targetProject: Project? {
        store.project(pickedProjectID ?? defaultProjectID ?? store.data.inbox.id) ?? store.data.inbox
    }

    /// The `#partial` being typed as the last word, if any.
    private var partialTag: String? {
        guard let last = text.split(separator: " ", omittingEmptySubsequences: false).last,
              last.hasPrefix("#") else { return nil }
        return String(last.dropFirst())
    }

    private var suggestions: [Project] {
        guard let partial = partialTag else { return [] }
        let n = QuickAdd.normalize(partial)
        return store.data.projects.filter { n.isEmpty || QuickAdd.normalize($0.name).hasPrefix(n) }
    }

    /// Replace the partial tag with the normalized name so the parser matches it exactly.
    private func complete(with p: Project) {
        guard let partial = partialTag else { return }
        text = String(text.dropLast(partial.count + 1)) + "#" + QuickAdd.normalize(p.name) + " "
    }

    private func submit() {
        if partialTag != nil, let first = suggestions.first { complete(with: first); return }
        guard store.quickAdd(text, defaultProjectID: targetProject?.id, inToday: inToday) != nil else { return }
        text = ""
        // Old typing history would otherwise capture the next ⌘Z meant for a task change.
        (NSApp.keyWindow?.firstResponder as? NSTextView)?.undoManager?.removeAllActions()
        focused = true
    }
}
