import SwiftUI
import MeToDoCore

/// The compact view under the menu bar icon (spec §5, mockups/menubar-popover.html).
struct PopoverView: View {
    @Environment(Store.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(\.openWindow) private var openWindow
    @Environment(ReminderScheduler.self) private var reminders

    var body: some View {
        @Bindable var ui = ui
        let data = store.data
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("View", selection: $ui.popoverShowsAll) {
                    Text("Today · \(Queries.today(data, now: ui.now).count)").tag(false)
                    Text("All · \(Queries.open(data).count)").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Button(action: openMain) { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(.borderless)
                    .help("Open MeToDo (⌘O)")
            }
            .padding([.horizontal, .top], 12)
            .padding(.bottom, 8)

            AddField(defaultProjectID: nil, inToday: !ui.popoverShowsAll, autofocus: true)
                .padding(.horizontal, 12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) { content(data) }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }

            if reminders.remindersOff {
                Button {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                } label: {
                    Label("Reminders are off · Fix…", systemImage: "bell.slash")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.orange)
                .padding(.horizontal, 12).padding(.vertical, 6)
            }
            if let error = store.saveError { WarningBanner(text: error) }
            Divider()
            footer
        }
        .frame(width: 340, height: 440)
        .task { await reminders.refreshAuthorization() }
        .background {
            // ⌘1 / ⌘2 switch tabs (spec §5).
            Group {
                Button("") { ui.popoverShowsAll = false }.keyboardShortcut("1")
                Button("") { ui.popoverShowsAll = true }.keyboardShortcut("2")
            }
            .opacity(0)
        }
    }

    @ViewBuilder private func content(_ data: AppData) -> some View {
        if ui.popoverShowsAll {
            let groups = Queries.grouped(Queries.open(data), projects: data.projects)
            if groups.isEmpty {
                Text("No tasks yet").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 30)
            }
            ForEach(groups) { g in
                GroupHeader(project: g.project).padding(.top, 4)
                ForEach(g.tasks) { TaskRow(task: $0, compact: true) }
            }
        } else {
            let today = Queries.today(data, now: ui.now)
            if today.isEmpty {
                let upNext = Queries.grouped(Queries.upNext(data, now: ui.now), projects: data.projects)
                AllClear(hasUpNext: !upNext.isEmpty)
                ForEach(upNext) { g in
                    GroupHeader(project: g.project).padding(.top, 4)
                    ForEach(g.tasks) { TaskRow(task: $0, alwaysShowSun: true, compact: true) }
                }
            } else {
                ForEach(today) { TaskRow(task: $0, showProjectTag: true, compact: true) }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Open MeToDo", action: openMain)
                .buttonStyle(.borderless)
                .keyboardShortcut("o")
            Spacer()
            Menu {
                Toggle("Launch at Login", isOn: Binding(get: { LoginItem.isOn }, set: { LoginItem.set($0) }))
                Button("Open MeToDo", action: openMain)
                Divider()
                Button("Quit MeToDo") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func openMain() {
        openWindow(id: "main")
        NSApp.activate()
    }
}
