import SwiftUI
import MeToDoCore

/// Quick choices, a month calendar and a time, for a task's reminder or a new task's due time.
struct ReminderPicker: View {
    @Environment(\.dismiss) private var dismiss
    let current: Date?
    let onSet: (Date?) -> Void
    @State private var day: Date
    @State private var time: Date

    init(current: Date?, onSet: @escaping (Date?) -> Void) {
        self.current = current
        self.onSet = onSet
        let start = current ?? Queries.at(hour: 9, daysFromNow: 1, now: Date())
        _day = State(initialValue: start)
        _time = State(initialValue: start)
    }

    var body: some View {
        let now = Date()
        let calendar = Calendar.current
        VStack(alignment: .leading, spacing: 0) {
            Text(current == nil ? "Remind me" : "Change reminder")
                .font(.headline)
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)

            VStack(spacing: 2) {
                QuickRow(icon: "clock", title: "In 1 hour", date: now.addingTimeInterval(3600), now: now) { set($0) }
                if calendar.component(.hour, from: now) < 18 {
                    QuickRow(icon: "moon.stars", title: "This evening", date: Queries.at(hour: 18, daysFromNow: 0, now: now), now: now) { set($0) }
                }
                QuickRow(icon: "sunrise", title: "Tomorrow morning", date: Queries.at(hour: 9, daysFromNow: 1, now: now), now: now) { set($0) }
                QuickRow(icon: "calendar", title: "Next Monday", date: Queries.at(hour: 9, daysFromNow: daysToNextMonday(now), now: now), now: now) { set($0) }
            }
            .padding(.horizontal, 8)

            Divider().padding(.vertical, 10)

            MonthGrid(day: $day, minDay: now)
                .padding(.horizontal, 14)

            HStack(spacing: 6) {
                ForEach(Self.chipHours, id: \.self) { hour in timeChip(hour) }
                otherTimeMenu
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.top, 10)

            Divider().padding(.top, 12)

            HStack {
                if current != nil {
                    Button("Remove", role: .destructive) { set(nil) }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                }
                Spacer()
                Button { set(custom) } label: {
                    Text(custom > now ? "Set · \(custom.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))"
                                      : "Pick a future time")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(custom <= now)
            }
            .padding(12)
        }
        .frame(width: 300)
    }

    /// The calendar's day at the chosen time.
    private var custom: Date {
        let t = Calendar.current.dateComponents([.hour, .minute], from: time)
        return Calendar.current.date(bySettingHour: t.hour ?? 9, minute: t.minute ?? 0, second: 0, of: day) ?? day
    }

    private static let chipHours = [9, 12, 15, 18]

    private var timeIsChip: Bool {
        let t = Calendar.current.dateComponents([.hour, .minute], from: time)
        return t.minute == 0 && Self.chipHours.contains(t.hour ?? -1)
    }

    private func timeChip(_ hour: Int) -> some View {
        let date = Queries.at(hour: hour, daysFromNow: 0, now: Date())
        let selected = Calendar.current.dateComponents([.hour, .minute], from: time) == DateComponents(hour: hour, minute: 0)
        return Button { time = date } label: {
            PillLabel(text: date.formatted(date: .omitted, time: .shortened), selected: selected)
        }
        .buttonStyle(.plain)
    }

    /// Any half hour of the day; shows the chosen time when it isn't one of the chips.
    private var otherTimeMenu: some View {
        Menu {
            ForEach(0..<48, id: \.self) { slot in
                let date = Queries.at(hour: 0, daysFromNow: 0, now: Date()).addingTimeInterval(Double(slot) * 1800)
                Button(date.formatted(date: .omitted, time: .shortened)) { time = date }
            }
        } label: {
            PillLabel(text: timeIsChip ? "Other" : time.formatted(date: .omitted, time: .shortened),
                      selected: !timeIsChip, chevron: true)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func daysToNextMonday(_ now: Date) -> Int {
        let weekday = Calendar.current.component(.weekday, from: now)   // 1 = Sunday, 2 = Monday
        let days = (9 - weekday) % 7
        return days == 0 ? 7 : days
    }

    private func set(_ date: Date?) {
        onSet(date)
        dismiss()
    }
}

/// One quick choice: icon, title, and the exact time it means, highlighted on hover.
private struct QuickRow: View {
    let icon: String
    let title: String
    let date: Date
    let now: Date
    let action: (Date) -> Void
    @State private var hovering = false

    var body: some View {
        Button { action(date) } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 18)
                    .foregroundStyle(hovering ? .primary : .secondary)
                Text(title)
                Spacer()
                Text(detail)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(hovering ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    /// "11:09 AM" for today, otherwise "Wed 9:00 AM".
    private var detail: String {
        Calendar.current.isDate(date, inSameDayAs: now)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}

private struct PillLabel: View {
    let text: String
    let selected: Bool
    var chevron = false

    var body: some View {
        HStack(spacing: 3) {
            Text(text).monospacedDigit().lineLimit(1)
            if chevron { Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold)) }
        }
        .font(.caption)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(selected ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
        .foregroundStyle(selected ? .white : .primary)
        .contentShape(Capsule())
        .fixedSize()
    }
}

/// A modern month calendar: circle selection, today tinted, days before `minDay` disabled.
private struct MonthGrid: View {
    @Binding var day: Date
    let minDay: Date
    @State private var month: Date

    init(day: Binding<Date>, minDay: Date) {
        _day = day
        self.minDay = minDay
        _month = State(initialValue: Self.startOfMonth(day.wrappedValue))
    }

    var body: some View {
        let calendar = Calendar.current
        VStack(spacing: 6) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 22, height: 22) }
                    .disabled(month <= Self.startOfMonth(minDay))
                Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 22, height: 22) }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 4)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.caption2.weight(.medium)).foregroundStyle(.secondary).frame(height: 18)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let date { cell(date, calendar) } else { Color.clear.frame(height: 30) }
                }
            }
        }
    }

    private func cell(_ date: Date, _ calendar: Calendar) -> some View {
        let selected = calendar.isDate(date, inSameDayAs: day)
        let isToday = calendar.isDateInToday(date)
        let disabled = date < calendar.startOfDay(for: minDay)
        return Button { day = date } label: {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 12, weight: selected || isToday ? .semibold : .regular))
                .monospacedDigit()
                .frame(width: 30, height: 30)
                .background {
                    if selected { Circle().fill(Color.accentColor) }
                    else if isToday { Circle().fill(Color.accentColor.opacity(0.15)) }
                }
                .foregroundStyle(selected ? AnyShapeStyle(.white) : disabled ? AnyShapeStyle(.tertiary)
                                 : isToday ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    /// Leading blanks for the first weekday, then each day of the month.
    private var cells: [Date?] {
        let calendar = Calendar.current
        let lead = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        return Array(repeating: nil, count: lead) + (0..<count).map { calendar.date(byAdding: .day, value: $0, to: month) }
    }

    private var weekdaySymbols: [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private func shift(_ months: Int) {
        month = Calendar.current.date(byAdding: .month, value: months, to: month) ?? month
    }

    private static func startOfMonth(_ date: Date) -> Date {
        Calendar.current.dateInterval(of: .month, for: date)?.start ?? date
    }
}
