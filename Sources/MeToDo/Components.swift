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
            .foregroundStyle(project.color.color)
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
    func rail(_ color: ProjectColor) -> some View {
        padding(.leading, 10)
            .overlay(alignment: .leading) { Rectangle().fill(color.color).frame(width: 2) }
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
                Button((p.id == selected ? "✓ " : "") + p.displayName) { onPick(p) }
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
        .foregroundStyle(project.color.color)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(project.color.color.opacity(0.14), in: Capsule())
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
