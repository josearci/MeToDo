# MeToDo — macOS To-Do App Design

**Date:** 2026-10-06
**Status:** Approved in brainstorming, pending written-spec review
**Mockups:** [`mockups/main-window.html`](mockups/main-window.html), [`mockups/menubar-popover.html`](mockups/menubar-popover.html) (open in a browser)

## 1. Goal

A minimal, native macOS to-do app for one person on one Mac. Tasks live in colored projects, can have one level of subtasks, can carry a reminder that reliably alerts, and are reachable at any time from a menu bar icon without opening the full window.

**Success looks like:**
- Capturing a task takes one click on the menu bar icon, typing, and Return.
- Reminders are never missed: they fire with the app closed and stay on screen until acted on.
- "What do I do now?" always has an answer: Today, or the Up next list when Today is empty.
- Installing or updating is one command.

**Constraints:** macOS only (no iPhone, no sync, no accounts). Local data only. Installed on this Mac only, so no notarization and no paid developer account.

**Out of scope (v1):** iPhone/iCloud sync, repeating tasks, notes/attachments, nested subtasks, search, Focus-mode breakthrough (time-sensitive notifications), localization of the UI (UI is English; task text can be any language).

## 2. Concepts

- **Project**: a name, one of 8 palette colors, an optional emoji. Ordered by the user. A built-in **📥 Inbox** project (gray) always exists. It can be renamed or recolored but not deleted.
- **Task**: a title, belongs to exactly one project, can be done or open, has an optional reminder time (`remindAt`), an optional manual "in Today" flag (`inToday`), and zero or more subtasks.
- **Subtask**: a title and a done flag. One level only. No reminders.
- **Today**: a computed view. An open task is in Today when `inToday == true` **or** `remindAt` falls on today or earlier (local calendar day).
  - `inToday` stays set until the task is completed (completing clears it) or the user removes it from Today.
- **All**: every open task, grouped by project in project order.

## 3. Visual design

Approved merged direction (see `mockups/main-window.html`):

- **Project color drives identity.** Task titles use the project color softened toward the text color: ~58% color mixed with near-white in dark mode, ~72% color mixed with near-black in light mode.
- Group headers (emoji + name) and the group's 2pt left rail use the full project color.
- Checkboxes are rounded squares (corner radius ≈ 5pt) stroked in the project color. Subtask checkboxes are smaller, and filled with the project color when done.
- Under the title is a small secondary metadata line, shown only when it has content, e.g. `◔ 1/4 · 🔔 Today 3:00 PM · ☀️`.
  - `◔ n/m` is the subtask progress, drawn in the project color.
  - The bell turns red when overdue.
- The app follows the system appearance (light/dark).

**Palette (dark / light hex):**

| Name   | Dark      | Light     |
|--------|-----------|-----------|
| gray   | `#9A9AA0` | `#8A8A8F` |
| red    | `#FF6B6B` | `#D93B3B` |
| orange | `#FF9F45` | `#C96A12` |
| yellow | `#F5C451` | `#C08A12` |
| green  | `#4CC38A` | `#1F9D63` |
| teal   | `#4CC9D0` | `#13838A` |
| blue   | `#5AA9FF` | `#2E6FD1` |
| purple | `#A78BFA` | `#7C5CD6` |

## 4. Main window

Layout: sidebar on the left, task list on the right (see mockup).

**Sidebar:** `☀️ Today n`, `📋 All n`, then a "Projects" label, then each project (color dot, emoji, name, open-task count), then `＋ New Project`.
- Drag projects to reorder them.
- Right-click a project → Edit… (name, color, emoji) / Delete…
- Delete asks for confirmation and deletes the project's tasks. It can be undone.

**Task list:**
- **Title.** The selected view's name and an open count.
- **Groups.** In All and Up next, tasks are grouped by project, each group with its header and rail. A single project's view shows just that group. Today is a flat list (see §6 for its order and the empty state).
- **Row.** A checkbox, the title and the meta line.
  - Hovering shows a drag handle on the left and ☀️ (toggle Today) and 🔔 (reminder picker) on the right.
- **Editing.** Click a title to edit it inline. Return saves and Escape cancels.
- **Subtasks.** Click `◔ n/m` (or press →/←) to expand or collapse them. The expanded list is indented and ends in a `＋ Add subtask` field. Return adds a subtask and keeps focus there for the next one. Tasks with no subtasks expose "Add subtask" via right-click and the → key.
- **Reminder picker.** A popover with *In 1 hour*, *This evening (6 PM)*, *Tomorrow 9 AM*, a date+time picker, and *Remove reminder*.
- **Completing.** Ticking a task fades it for ~1s (clicking again during that time cancels), then it moves into a collapsed `▸ Done · n` section at the end of the current view. Done has a "Clear" action that permanently removes the done tasks shown in that view (undoable via ⌘Z while the app is open).
- **Completion rules.** Completing all subtasks does not complete the parent. Completing the parent leaves its subtasks as they are.
- **Reordering.** Drag within a project group to reorder. Drop a task on a sidebar project to move it there. Right-click a task → Move to ▸ project / Delete.
- **Add field.** Pinned at the bottom (see §7).

**Keyboard (main window):**
- ⌘N: focus the Add field
- ↑/↓: move the selection
- Space: complete or uncomplete
- Return: edit the title
- ⌫: delete
- ⌘Z / ⇧⌘Z: undo / redo
- ⌘T: toggle Today
- →/←: expand or collapse subtasks
- ⌘1: Today
- ⌘2: All
- ⌘3…⌘9: projects in sidebar order

## 5. Menu bar popover

See `mockups/menubar-popover.html`.

**Icon.** A monochrome checkmark template icon. It shows a small red dot while any open task is overdue.

**Popover.** About 340pt wide, with a scrolling list. From top to bottom:
1. A `Today · n | All · n` segmented control, plus ⤢ to open the main window.
2. The Add field. It sits at the top here so it's next to the cursor, and it's focused when the popover opens.
3. The list.
   - **Today** is flat, and each row shows a small project tag (emoji + name in the project color) instead of group headers.
   - **All** uses project group headers.
4. A footer with `Open MeToDo ⌘O` on the left and a ⚙︎ menu on the right: Launch at Login (checkmark toggle), Open MeToDo, Quit MeToDo.

**What you can do in the popover.** Complete, edit a title inline, expand subtasks, tick and add subtasks, ☀️ toggle, and the 🔔 picker. Moving tasks and editing projects happen only in the main window.

## 6. Today ordering and empty state

**Order:**
1. Overdue tasks, oldest reminder first.
2. Tasks with a reminder later today, by time.
3. ☀️-picked tasks without a reminder today, in project order and then task order.

**Empty state.** When Today has no open tasks, it shows `✓ All clear for today` followed by **Up next**: all other open tasks grouped by project, each with a visible ☀️ button that pulls it into Today. This applies to both the window and the popover.

## 7. Quick add

**Input example:** `Call Ana #sprint tomorrow 9am`

**`#token` (project).** `#` followed by non-space characters.
- The token is matched case- and diacritic-insensitively against project names with spaces and emoji removed.
- An exact match wins. Otherwise a unique prefix match is used.
- A matched token is removed from the title. An unmatched token stays in the title as typed.
- While typing after `#`, an autocomplete list of projects is shown, and Tab or Return accepts the suggestion.

**Date/time.** Uses Foundation's `NSDataDetector` (`.date`).
- The first date match is taken as `remindAt` and removed from the title.
- If the matched text contains no time, the reminder is set to 9:00 AM that day.
- English phrases are the supported set. Other languages may work but aren't guaranteed.

**Default project.** With no matched `#`, the task goes to the project being viewed. In Today or All it goes to Inbox.

**Today.** Tasks added while viewing Today get `inToday = true`.

**Empty title.** If the title is empty after stripping, nothing is created.

## 8. Reminders

Uses `UserNotifications` local notifications scheduled with the system, so they fire even when MeToDo isn't running.

**Content and identity:**
- The notification identifier is the task id.
- The title is the task title. The subtitle is the project's emoji and name.
- Category `TASK_REMINDER` has the actions **Complete**, **Snooze 10 min**, **Snooze 1 hr** and **Tomorrow 9 AM**.

**Alert style.** `Info.plist` sets `NSUserNotificationAlertStyle = alert`, so reminders default to persistent alerts. The user can still change this in System Settings.

**Actions.** The notification delegate applies the action to the Store. Snoozing sets `remindAt` to the new time, so the task stays in Today showing that time. Clicking the notification body opens the main window with the task selected.

**Scheduling rules:**
- A reminder is scheduled only when `remindAt > now` and the task is open.
- Completing a task, deleting it, removing its reminder or changing its reminder replaces or cancels the pending request.
- **Self-heal on launch.** Remove all pending requests, then schedule one for every open task with a future `remindAt`.
- The decision of what should be scheduled is a pure function, `reminderPlan(tasks, now) -> [(taskID, date)]`, so it can be tested without the system.

**Overdue dot.** Recomputed whenever the Store changes and on a 60-second timer.

**Permission.**
- **Request.** Notification permission is requested on first launch.
- **If denied.** The popover shows a `Reminders are off · Fix…` row that opens System Settings › Notifications.

## 9. App lifecycle and install

- **Menu bar agent.** `LSUIElement = true`, so there's no Dock icon by default. While the main window is open the activation policy switches to `.regular` (Dock icon, ⌘-Tab). It switches back to `.accessory` when the window closes.
- **Closing the window.** This doesn't quit. Only ⚙︎ → Quit does.
- **Launch at login.** Uses `SMAppService.mainApp`. It's registered on first launch and can be toggled from the ⚙︎ menu.
- **First launch.** Creates the Inbox, requests notification permission, registers the login item and opens the main window once. There are no onboarding screens.
- **Requirements.** macOS 15 or later and Swift 6. No third-party dependencies.

**Repository layout (Swift package, also opens in Xcode):**
```
Package.swift
Sources/MeToDoCore/      # pure logic, no UI: Models, Store, QuickAdd, ReminderPlan, Persistence
Sources/MeToDo/          # SwiftUI app: App entry, Views, ReminderScheduler (UserNotifications), LoginItem
Tests/MeToDoCoreTests/   # Swift Testing
Resources/Info.plist
install.sh
```

**`install.sh`:**
1. Runs `swift build -c release`.
2. Assembles `MeToDo.app` from the release binary and `Resources/Info.plist` (bundle id `com.josearci.metodo`, `LSUIElement`, alert style).
3. Ad-hoc signs it (`codesign --force --sign -`).
4. Quits any running copy.
5. Copies it to `/Applications` and launches it.

Re-running the script updates the app in place. Data is untouched.

## 10. Data and persistence

**Location.** `~/Library/Application Support/MeToDo/data.json`. The app isn't sandboxed, so the path is predictable for backups.

**Format:**
```json
{
  "version": 1,
  "projects": [
    { "id": "UUID", "name": "Inbox", "color": "gray", "emoji": "📥", "isInbox": true }
  ],
  "tasks": [
    {
      "id": "UUID", "projectID": "UUID", "title": "…",
      "isDone": false, "completedAt": null,
      "remindAt": "2026-10-06T15:00:00Z", "inToday": false,
      "subtasks": [ { "id": "UUID", "title": "…", "isDone": false } ]
    }
  ]
}
```

**Ordering.** Array order is display order: projects in sidebar order, tasks in order within their project.

**Model naming.** The Swift type is `TaskItem`, to avoid clashing with Swift Concurrency's `Task`.

**Saving:**
- Debounced ~0.5s after any change, and also on quit.
- Uses an atomic write (`Data.write(options: .atomic)`).
- On each launch, after a successful load, the loaded file is copied to `data.json.bak`.

## 11. Error handling

| Situation | Behavior |
|---|---|
| `data.json` missing | Fresh start with Inbox. |
| `data.json` unreadable or undecodable | Never overwritten: renamed to `data-corrupt-<timestamp>.json`, app starts fresh, an alert tells the user the file name. |
| Save fails | Data stays in memory, a non-blocking warning appears in the window/popover, the next change retries. |
| Notifications denied | "Reminders are off · Fix…" row (§8). Reminders still show as overdue in the app. |
| Reminder time in the past | Not scheduled. The task shows as overdue. |
| Login item registration fails | ⚙︎ toggle shows off. No alert. |
| Destructive actions (delete task/project, Clear done) | Undoable with ⌘Z for the session. Delete project also asks for confirmation. |

## 12. Testing

**Automated (Swift Testing, `swift test`, `MeToDoCore` only):**
- **QuickAdd:** `#token` exact, prefix, ambiguous and unmatched. Date with and without a time (9 AM default). Stripping text from the title. An empty result creates nothing.
- **Today membership and ordering:** `inToday`, today, overdue, future and done tasks. Completing clears `inToday`. Empty state → Up next contents.
- **Store mutations:** complete/uncomplete, snooze (10m, 1h, tomorrow 9 AM), move project, delete project cascade, Inbox not deletable.
- **`reminderPlan`:** includes only open tasks with a future `remindAt`.
- **Persistence:** save→load round trip. A corrupt file is renamed and not overwritten. `.bak` is written after a successful load.

**Manual checklist (real app after `./install.sh`):**
1. Add a task from the popover using `#project tomorrow 9am`.
2. Add and tick subtasks, and confirm the `◔` progress updates.
3. Toggle ☀️, and check the Today order and the empty state.
4. Set a reminder 1 minute out, quit the app, and confirm the alert still fires and stays on screen.
5. Snooze from the alert, and confirm the new time shows in Today.
6. Complete a task from the alert.
7. Reboot or log out and back in, and confirm the menu bar icon returns.
8. Check light and dark mode.
