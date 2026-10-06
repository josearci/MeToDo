import SwiftUI
import MeToDoCore

/// "Add task" input. Understands `#project` and dates via Store.quickAdd (spec §7).
struct AddField: View {
    @Environment(Store.self) private var store
    @Environment(UIState.self) private var ui
    let defaultProjectID: UUID?
    let inToday: Bool
    var autofocus = false
    @State private var text = ""
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
                    Text("#project · tomorrow 9am").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
        }
        .onChange(of: ui.focusAddFieldToken) { focused = true }
        .onAppear { if autofocus { focused = true } }
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
        guard store.quickAdd(text, defaultProjectID: defaultProjectID, inToday: inToday) != nil else { return }
        text = ""
        focused = true
    }
}
