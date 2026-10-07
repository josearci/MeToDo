import SwiftUI
import AppKit
import MeToDoCore

/// Create or edit a project: emoji tile, name, and a color (8 presets, colors already used, or any custom color).
struct ProjectEditor: View {
    @Environment(Store.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(\.dismiss) private var dismiss
    let original: Project?
    @State private var name: String
    @State private var emoji: String
    @State private var color: ProjectColor
    /// "#RRGGBB" when a custom color is chosen; nil means the palette `color`.
    @State private var customHex: String?
    @State private var colorPanel = ColorPanelBridge()
    @State private var showEmojis = false
    @FocusState private var nameFocused: Bool

    init(project: Project?) {
        original = project
        _name = State(initialValue: project?.name ?? "")
        _emoji = State(initialValue: project?.emoji ?? "")
        _color = State(initialValue: project?.color ?? .blue)
        _customHex = State(initialValue: project?.customColor)
    }

    /// What the project will look like, for the emoji tile.
    private var preview: Project {
        Project(name: name, color: color, emoji: emoji.isEmpty ? nil : emoji, customColor: customHex)
    }

    /// Custom colors already used by projects, offered for reuse.
    private var usedCustomColors: [String] {
        var seen = Set<String>()
        return (store.data.projects.compactMap(\.customColor) + [customHex].compactMap { $0 })
            .filter { seen.insert($0).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(original == nil ? "New Project" : "Edit Project")
                .font(.title3.weight(.semibold))

            HStack(spacing: 14) {
                Button { showEmojis = true } label: { EmojiTile(project: preview) }
                    .buttonStyle(.plain)
                    .help("Choose an emoji")
                    .popover(isPresented: $showEmojis, arrowEdge: .bottom) { EmojiGrid(selection: $emoji) }
                TextField("Project name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .medium))
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    .focused($nameFocused)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Color").font(.subheadline).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 30, maximum: 30), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(ProjectColor.allCases, id: \.self) { c in
                        Swatch(fill: c.color, selected: customHex == nil && color == c, label: c.rawValue.capitalized) {
                            color = c
                            customHex = nil
                        }
                    }
                    ForEach(usedCustomColors, id: \.self) { hex in
                        Swatch(fill: Project(name: "", color: .gray, customColor: hex).tint.color, selected: customHex == hex, label: hex) {
                            customHex = hex
                        }
                    }
                    customColorButton
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(original == nil ? "Create" : "Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 380)
        .onAppear { nameFocused = original == nil }
        .onDisappear { colorPanel.close() }
    }

    /// Rainbow "+" that opens the system color panel; the picked color becomes the project's color.
    private var customColorButton: some View {
        Button {
            colorPanel.open(initial: NSColor(preview.tint.color)) { customHex = Self.hex($0) }
        } label: {
            Circle()
                .fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red], center: .center))
                .frame(width: 24, height: 24)
                .overlay { Image(systemName: "plus").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white) }
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Pick any color")
    }

    private static func hex(_ color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X", Int(round(rgb.redComponent * 255)),
                      Int(round(rgb.greenComponent * 255)), Int(round(rgb.blueComponent * 255)))
    }

    private func save() {
        if var p = original {
            p.name = name
            p.emoji = emoji
            p.color = color
            p.customColor = customHex
            store.updateProject(p)
        } else if let p = store.addProject(name: name, color: color, emoji: emoji, customColor: customHex) {
            ui.sidebar = .project(p.id)
        }
        dismiss()
    }
}

private struct Swatch: View {
    let fill: Color
    let selected: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(fill)
                .frame(width: 22, height: 22)
                .overlay {
                    if selected { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white) }
                }
                .padding(3)
                .overlay(Circle().strokeBorder(selected ? fill : .clear, lineWidth: 2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The project's emoji on a tile tinted with its color; click to change.
private struct EmojiTile: View {
    let project: Project

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(project.tint.color.opacity(0.22))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(project.tint.color.opacity(0.55), lineWidth: 1))
            .frame(width: 52, height: 52)
            .overlay {
                if let emoji = project.emoji, !emoji.isEmpty {
                    Text(emoji).font(.system(size: 28))
                } else {
                    Image(systemName: "face.smiling").font(.system(size: 22)).foregroundStyle(project.tint.color)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white, project.tint.color)
                    .offset(x: 5, y: 5)
            }
            .contentShape(Rectangle())
    }
}

/// Common emojis in a grid, plus any other emoji typed or picked from the system palette.
private struct EmojiGrid: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var other = ""
    @FocusState private var otherFocused: Bool

    private static let emojis = [
        "📥", "💼", "🏠", "🎓", "🚀", "💡", "📚", "🧪", "🎯", "🛒",
        "💪", "🏃", "✈️", "🎨", "🎵", "💻", "📊", "🧠", "❤️", "🌱",
        "🐶", "🍳", "🧾", "🔧", "📅", "⭐️", "🔥", "🎮", "🏀", "⚽️",
        "🏈", "🎬", "📸", "💰", "🏦", "🩺", "🧹", "🎁", "⛽️", "🏳️‍🌈",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 4), count: 10), spacing: 4) {
                ForEach(Self.emojis, id: \.self) { e in
                    EmojiCell(emoji: e, selected: e == selection) { pick(e) }
                }
            }
            Divider()
            HStack(spacing: 8) {
                TextField("Any emoji", text: $other)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    .frame(width: 100)
                    .focused($otherFocused)
                    .onChange(of: other) { _, typed in
                        if let first = typed.first, first.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation || $0.value > 0x2000 && $0.properties.isEmoji }) {
                            pick(String(first))
                        }
                    }
                Button {
                    otherFocused = true
                    DispatchQueue.main.async { NSApp.orderFrontCharacterPalette(nil) }
                } label: { Label("Browse all", systemImage: "face.smiling") }
                Spacer()
                if !selection.isEmpty {
                    Button("None") { pick("") }.foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .frame(width: 372)
    }

    private func pick(_ emoji: String) {
        selection = emoji
        dismiss()
    }
}

private struct EmojiCell: View {
    let emoji: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(emoji)
                .font(.system(size: 20))
                .frame(width: 32, height: 32)
                .background(selected ? Color.accentColor.opacity(0.3) : hovering ? Color.secondary.opacity(0.15) : .clear,
                            in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Opens the shared system color panel and reports each color the user picks.
final class ColorPanelBridge: NSObject {
    /// The bridge the shared panel currently reports to (the panel exposes no target getter).
    private(set) static weak var active: ColorPanelBridge?
    private var onChange: (NSColor) -> Void = { _ in }

    func open(initial: NSColor, onChange: @escaping (NSColor) -> Void) {
        self.onChange = onChange
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.color = initial
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        Self.active = self
        panel.orderFront(nil)
    }

    func close() {
        let panel = NSColorPanel.shared
        guard Self.active === self else { return }
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.orderOut(nil)
        Self.active = nil
    }

    @objc func colorChanged(_ panel: NSColorPanel) { onChange(panel.color) }
}
