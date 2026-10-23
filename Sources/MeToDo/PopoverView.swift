import SwiftUI
import MeToDoCore

/// The compact view under the menu bar icon (spec §5, mockups/menubar-popover.html).
struct PopoverView: View {
    @Environment(Store.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(Updater.self) private var updater
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

            AddField(placement: .popover, autofocus: true)
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
            if case .ready(let version) = updater.state {
                Button { updater.installAndRelaunch(saving: store) } label: {
                    Label("MeToDo \(version) is ready · Restart to update", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.accentColor)
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
            groupList(groups)
        } else {
            let today = Queries.today(data, now: ui.now)
            if today.isEmpty {
                let upNext = Queries.grouped(Queries.upNext(data, now: ui.now), projects: data.projects)
                AllClear(hasUpNext: !upNext.isEmpty)
                groupList(upNext, alwaysShowSun: true)
            } else {
                // One list in Today order (priority first), each task tagged with its project.
                PlannedLabel(minutes: Queries.planned(today, now: ui.now))
                ForEach(today) { t in
                    TaskRow(task: t, showProjectTag: true, compact: true)
                        .rail(data.projects.first { $0.id == t.projectID }?.tint ?? ProjectColor.gray.tint)
                }
            }
        }
        let done = ui.popoverShowsAll ? Queries.done(data) : Queries.doneToday(data, now: ui.now)
        if !done.isEmpty {
            DoneHeader(count: done.count) { store.clearDone(done.map(\.id)) }
            ForEach(done) { TaskRow(task: $0, showProjectTag: true, compact: true) }
        }
    }

    @ViewBuilder private var updateMenuItem: some View {
        switch updater.state {
        case .ready(let version):
            Button("Restart to Update to \(version)") { updater.installAndRelaunch(saving: store) }
        case .downloading(let version):
            Text("Downloading \(version)…")
        case .checking:
            Text("Checking for updates…")
        case .upToDate:
            Button("Up to Date · Check Again") { Task { await updater.check() } }
        case .failed(let message):
            Text(message)
            Button("Try Again") { Task { await updater.check() } }
        case .idle:
            Button("Check for Updates") { Task { await updater.check() } }
        }
    }

    private var footer: some View {
        HStack {
            Button("Open MeToDo", action: openMain)
                .buttonStyle(.borderless)
                .keyboardShortcut("o")
            Spacer()
            Menu {
                Text("Show or hide from anywhere: \(StatusItemController.hotKeyDescription)")
                Divider()
                Text("MeToDo \(updater.currentVersion)")
                if updater.canUpdate { updateMenuItem }
                Divider()
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

    private func groupList(_ groups: [TaskGroup], alwaysShowSun: Bool = false) -> some View {
        ForEach(groups) { g in
            GroupHeader(project: g.project).rail(g.project.tint, bar: false).padding(.top, 4)
            ForEach(g.tasks) { TaskRow(task: $0, alwaysShowSun: alwaysShowSun, compact: true).rail(g.project.tint) }
        }
    }

    /// Going to the full window closes this popover; no point keeping both open.
    private func openMain() {
        ui.openMainWindow()   // also closes this popover
    }
}
