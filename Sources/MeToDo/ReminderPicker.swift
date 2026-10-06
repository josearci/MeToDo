import SwiftUI
import MeToDoCore

struct ReminderPicker: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let taskID: UUID
    let current: Date?
    @State private var custom: Date

    init(taskID: UUID, current: Date?) {
        self.taskID = taskID
        self.current = current
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
        store.setReminder(taskID, date)
        dismiss()
    }
}
