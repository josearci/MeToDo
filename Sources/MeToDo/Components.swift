import SwiftUI
import MeToDoCore

/// Rounded-square checkbox in the project color (approved merged design).
struct CheckBox: View {
    let isOn: Bool
    let color: Color
    var size: CGFloat = 14
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: size * 0.36)
                .fill(isOn ? color : .clear)
                .strokeBorder(color, lineWidth: 1.5)
                .overlay {
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: size * 0.6, weight: .bold))
                            .foregroundStyle(.background)
                    }
                }
                .frame(width: size, height: size)
                // A plain-style button only takes clicks on drawn pixels, and an unchecked box is just a
                // 1.5pt outline, so clicks in its middle fell through to the row. Make the whole box, plus
                // a little margin, clickable.
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(-4)
        .accessibilityLabel(isOn ? "Mark as not done" : "Mark as done")
    }
}

/// The ◔ subtask progress ring.
struct ProgressRing: View {
    let fraction: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.3), lineWidth: 1.5)
            Circle().trim(from: 0, to: fraction).stroke(color, lineWidth: 1.5).rotationEffect(.degrees(-90))
        }
        .frame(width: 9, height: 9)
    }
}

struct GroupHeader: View {
    let project: Project

    var body: some View {
        Text(project.displayName)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(project.tint.color)
            .padding(.top, 6)
    }
}

/// Today's empty state (spec §6).
struct AllClear: View {
    let hasUpNext: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "checkmark.circle").font(.system(size: 22))
            Text("All clear for today")
            if hasUpNext {
                Text("Up next · click \(Image(systemName: "sun.max")) to pull into Today")
                    .font(.caption).foregroundStyle(.tertiary).padding(.top, 8)
            }
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }
}

struct WarningBanner: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .padding(8)
            .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            .padding(8)
    }
}

extension View {
    /// The project's 2pt color rail on the leading edge, continuous across rows.
    /// `bar: false` keeps the same indent without the bar (group headers).
    func rail(_ tint: ProjectTint, bar: Bool = true) -> some View {
        padding(.leading, 10)
            .overlay(alignment: .leading) { if bar { Rectangle().fill(tint.color).frame(width: 2) } }
            .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
            .listRowSeparator(.hidden)
    }
}

/// Pick a project: where a new task goes (Add field) or where an existing task moves (task row).
struct ProjectMenu<MenuLabel: View>: View {
    @Environment(Store.self) private var store
    let selected: UUID?
    let onPick: (Project) -> Void
    @ViewBuilder let label: () -> MenuLabel

    var body: some View {
        Menu {
            ForEach(store.data.projects) { p in
                // Toggle gives the native checkmark; the dot shows the project's color.
                Toggle(isOn: Binding(get: { p.id == selected }, set: { _ in onPick(p) })) {
                    ProjectMenuLabel(project: p)
                }
            }
        } label: {
            label()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// The colored project chip used as the Add field's project picker.
struct ProjectChip: View {
    let project: Project

    var body: some View {
        HStack(spacing: 4) {
            Text(project.displayName)
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
        }
        .font(.caption)
        .foregroundStyle(project.tint.color)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(project.tint.color.opacity(0.14), in: Capsule())
    }
}

/// Finished tasks stay visible (crossed out) under this header until cleared into the history.
struct DoneHeader: View {
    let count: Int
    let onClear: () -> Void

    var body: some View {
        HStack {
            Text("Done · \(count)")
            Spacer()
            Button("Clear done", action: onClear)
                .buttonStyle(.borderless)
                .help("Remove finished tasks from the list. They're kept in your history.")
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.top, 10)
    }
}

/// The Add field's time chip: "Time" until a time is picked, then e.g. "Tomorrow 9:00 AM".
struct TimeChip: View {
    let date: Date?
    let now: Date

    var body: some View {
        Label(date.map { Queries.reminderLabel($0, now: now) } ?? "Time", systemImage: "bell")
            .font(.caption)
            .foregroundStyle(date == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background((date == nil ? Color.secondary : .orange).opacity(0.14), in: Capsule())
    }
}

/// Hands back the NSWindow hosting a SwiftUI view.
struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onWindow(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Notes shown when a task is expanded. Saved as you type; ⌘Z undoes typing.
/// Web links in the text are clickable (open in the browser); click anywhere else to edit.
struct NotesEditor: View {
    @Environment(Store.self) private var store
    let task: TaskItem
    @State private var text: String

    init(task: TaskItem) {
        self.task = task
        _text = State(initialValue: task.notes)
    }

    var body: some View {
        NotesTextView(text: $text)
            .padding(.horizontal, 4).padding(.vertical, 4)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Add notes…")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: text) { _, new in store.setNotes(task.id, new) }
            .onChange(of: task.notes) { _, new in if new != text { text = new } }
    }
}

/// A plain-text NSTextView (TextEditor can't show links) that marks web links as you type. The links are
/// display-only attributes; the notes stay plain text. NSTextView itself opens a clicked link in the default
/// browser and shows the pointing hand over it.
private struct NotesTextView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        // TextKit 1, so sizeThatFits can measure with the layout manager.
        let textView = NSTextView(usingTextLayoutManager: false)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.font = .systemFont(ofSize: 12.5)
        textView.textColor = .labelColor
        textView.string = text
        textView.delegate = context.coordinator
        Self.markLinks(textView)
        let scroll = NotesScrollView()
        scroll.documentView = textView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scroll.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
        Self.markLinks(textView)
    }

    /// As tall as the text at the offered width, kept within 44–160pt (longer notes scroll). Clamped here, not
    /// with .frame(minHeight:maxHeight:), which lets a representable spill out of the box.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        guard let width = proposal.width, let textView = nsView.documentView as? NSTextView,
              let layout = textView.layoutManager, let container = textView.textContainer else { return nil }
        container.size.width = width
        layout.ensureLayout(for: container)
        return CGSize(width: width, height: min(max(ceil(layout.usedRect(for: container).height), 44), 160))
    }

    static func markLinks(_ textView: NSTextView) {
        guard let storage = textView.textStorage, !textView.hasMarkedText() else { return }   // not mid-IME input
        storage.beginEditing()
        storage.removeAttribute(.link, range: NSRange(location: 0, length: storage.length))
        for link in Links.find(in: storage.string) { storage.addAttribute(.link, value: link.url, range: link.range) }
        storage.endEditing()
    }

    /// Keeps the text view at least as tall as the box, so clicking below short notes still edits them.
    final class NotesScrollView: NSScrollView {
        override func tile() {
            super.tile()
            guard let textView = documentView as? NSTextView, textView.minSize.height != contentSize.height else { return }
            textView.minSize.height = contentSize.height
            textView.sizeToFit()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            NotesTextView.markLinks(textView)
            textView.enclosingScrollView?.invalidateIntrinsicContentSize()   // re-measure as lines are added
        }
    }
}

/// A menu item label: the project's color as a dot, then its emoji and name.
struct ProjectMenuLabel: View {
    let project: Project

    var body: some View {
        Label { Text(project.displayName) } icon: { Image(nsImage: Self.dot(NSColor(project.tint.color))) }
    }

    /// Menus re-tint template images, so the dot is a non-template image drawn in the color.
    static func dot(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
