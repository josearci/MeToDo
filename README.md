<p align="center">
  <img src="Resources/AppIcon-1024.png" width="128" alt="MeToDo icon">
</p>

<h1 align="center">MeToDo</h1>

<p align="center">A minimal to-do app for macOS that lives in your menu bar.</p>

<p align="center">
  <img src="docs/images/main-window.png" width="820" alt="MeToDo main window showing tasks grouped by colored projects">
</p>

## Install

Paste this into Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/josearci/MeToDo/main/install.sh | bash
```

It downloads the latest release, puts **MeToDo.app** in your Applications folder and starts it. A ✓ appears in your menu bar.

- **Requirements:** macOS 15 or later. Works on Apple Silicon and Intel Macs.
- **Updates:** MeToDo keeps itself up to date. Every change merged into `main` becomes a new release. The app checks for one at launch and every few hours, downloads it in the background, and shows **“Restart to update”** in the menu bar popover.

## What it does

**Projects with colors and emoji.** Group tasks into projects, each with an emoji and one of eight preset colors, or any custom color. Task titles and the color bar beside them take the project's color, so you can tell projects apart at a glance.

**Today and All.**
- **All** shows everything, grouped by project.
- **Today** shows tasks due today, tasks that are overdue, and anything you pull in with ☀️.
- When Today is empty, you see **Up next**, so there's always something to pick.

**Notes and subtasks.** Click a task to expand it. You'll see its notes and its subtasks, with a progress ring such as ◔ 1/3.

<p align="center">
  <img src="docs/images/today-expanded.png" width="820" alt="Today view with a task expanded to show notes and subtasks">
</p>

**Reminders that don't get lost.**
- Alerts stay on screen until you act on them: **Complete**, **Snooze 10 min**, **Snooze 1 hr** or **Tomorrow 9 AM**.
- They fire even when MeToDo isn't running.
- The menu bar icon shows a red dot while something is overdue.

**From the menu bar, anywhere.**
- Click the ✓, or press **⌃⌥M** (Control + Option + M) from any app, to open a compact view of your tasks.
- The popover has its own Add field, Today and All tabs, and everything else you need for a quick check.

<p align="center">
  <img src="docs/images/menu-bar-popover.png" width="340" alt="Menu bar popover with Today's tasks">
  &nbsp;&nbsp;
  <img src="docs/images/time-picker.png" width="300" alt="Reminder picker with quick choices, a month calendar and time chips">
</p>

**Quick add.** Type naturally in the Add field:

| You type | You get |
|---|---|
| `Call Ana #work tomorrow 9am` | a task in **Work** with a reminder tomorrow at 9:00 |
| `Pay rent friday` | a reminder on Friday at 9:00 |
| `Stretch in 2 hours` | a reminder two hours from now |

You can also choose the project and time with the chips at the end of the Add field.

**Done stays visible.** Finished tasks stay crossed out at the bottom until you press **Clear done**. Cleared tasks are kept in a history in your data file, ready for stats later: when each was created, completed and due, and how often it was snoozed.

<p align="center">
  <img src="docs/images/project-editor.png" width="380" alt="Project editor with emoji tile, name and color swatches">
  &nbsp;&nbsp;
  <img src="docs/images/compact-sidebar.png" width="440" alt="Sidebar dragged narrow, showing only project emoji">
</p>

**A sidebar that gets out of the way.** Drag the sidebar narrow and it turns into a strip of big project emoji.

## Keyboard

| Keys | Action |
|---|---|
| ⌃⌥M | Show or hide MeToDo from anywhere |
| ⌘N | New task |
| ⌘1 · ⌘2 · ⌘3… | Today · All · projects |
| Space | Complete the selected task |
| Return | Rename the selected task |
| ⌘T | Add to Today or remove from it |
| → / ← | Expand or collapse a task |
| ⌘Z / ⇧⌘Z | Undo / redo |

## Your data

- **Where it lives:** all your tasks are stored on your Mac, in `~/Library/Application Support/MeToDo/data.json`. A backup copy, `data.json.bak`, is refreshed every time the app starts. To back up, copy that folder.
- **No account, no sync, no tracking.** The only network request MeToDo makes is reading the public release info from GitHub to check for updates.

## Uninstall

Quit MeToDo from the ⚙︎ menu in its popover, then delete **MeToDo.app** from Applications. To remove your tasks too, also delete `~/Library/Application Support/MeToDo`.

## Development

```bash
swift test                    # core tests (models, Today logic, quick add, store, updates)
./scripts/dev-install.sh      # build this checkout and install it into /Applications
```

**How a release happens:** every push to `main` runs `.github/workflows/release.yml`. It runs the tests, builds a universal `MeToDo.app` with `scripts/build-app.sh`, and publishes it as a GitHub Release tagged `v1.0.<commit count>`. Installed copies pick it up on their next update check.

Builds are ad-hoc signed, not notarized. The installer downloads with `curl`, which doesn't trigger Gatekeeper's warning, and the app downloads its own updates the same way.

**To change the app icon:** run `./scripts/make-icns.sh path/to/logo.png`.

The design spec and implementation plan are in [`docs/superpowers`](docs/superpowers).
