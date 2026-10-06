import SwiftUI
import MeToDoCore

/// Quick choices plus a custom date/time. Used for a task's reminder and for a new task's time.
struct ReminderPicker: View {
    @Environment(\.dismiss) private var dismiss
    let current: Date?
    let onSet: (Date?) -> Void
    @State private var custom: Date

    init(current: Date?, onSet: @escaping (Date?) -> Void) {
        self.current = current
        self.onSet = onSet
        _custom = State(initialValue: current ?? Date().addingTimeInterval(3600))
    }

    var body: some View {
        let now = Date()
        VStack(alignment: .leading, spacing: 6) {
            preset("In 1 hour", now.addingTimeInterval(3600))
            if Calendar.current.component(.hour, from: now) < 18 {
                preset("This evening (6 PM)", Queries.at(hour: 18, daysFromNow: 0, now: now))
            }
            preset("Tomorrow 9 AM", Queries.at(hour: 9, daysFromNow: 1, now: now))
            Divider()
            DatePicker("Custom", selection: $custom).labelsHidden()
            HStack {
                if current != nil { Button("Remove", role: .destructive) { set(nil) } }
                Spacer()
                Button("Set") { set(custom) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 240)
    }

    private func preset(_ title: String, _ date: Date) -> some View {
        Button { set(date) } label: {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderless)
    }

    private func set(_ date: Date?) {
        onSet(date)
        dismiss()
    }
}
