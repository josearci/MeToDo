import SwiftUI
import AppKit
import MeToDoCore

struct AppCommands: Commands {
    let store: Store
    let ui: UIState
    let undoManager: UndoManager

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Task") {
                ui.openMainWindowToken += 1
                ui.focusAddFieldToken += 1
            }
            .keyboardShortcut("n")
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { undo(redo: false) }.keyboardShortcut("z")
            Button("Redo") { undo(redo: true) }.keyboardShortcut("z", modifiers: [.command, .shift])
        }
        CommandMenu("Task") {
            Button("Toggle Today") { if let id = ui.selectedTaskID { store.toggleToday(id) } }
                .keyboardShortcut("t")
        }
        CommandGroup(before: .sidebar) {
            Button("Today") { ui.sidebar = .today }.keyboardShortcut("1")
            Button("All") { ui.sidebar = .all }.keyboardShortcut("2")
            ForEach(Array(store.data.projects.prefix(7).enumerated()), id: \.element.id) { index, p in
                Button(p.displayName) { ui.sidebar = .project(p.id) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 3))))
            }
            Divider()
        }
    }

    /// A text field being edited keeps its own typing undo; otherwise undo task changes.
    private func undo(redo: Bool) {
        let textUndo = (NSApp.keyWindow?.firstResponder as? NSTextView)?.undoManager
        let canText = redo ? textUndo?.canRedo : textUndo?.canUndo
        let target = canText == true ? textUndo! : undoManager
        if redo { target.redo() } else { target.undo() }
    }
}
