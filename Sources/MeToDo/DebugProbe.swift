#if DEBUG
import AppKit
import SwiftUI
import MeToDoCore

/// Debug builds only: lets an outside test script see the app without screen-recording permission.
/// `METODO_DATA=/path/data.json` points the app at test data; posting the distributed notification
/// "com.josearci.metodo.probe" writes a PNG of every visible window plus state.json to /tmp/metodo-probe/.
@MainActor
enum DebugProbe {
    static var dataURL: URL? {
        ProcessInfo.processInfo.environment["METODO_DATA"].map { URL(fileURLWithPath: $0) }
    }

    static func install(store: Store, ui: UIState, reminders: ReminderScheduler) {
        self.reminders = reminders
        probeStore = store
        probeUI = ui
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.josearci.metodo.probe"), object: nil, queue: .main
        ) { note in
            let info = note.userInfo ?? [:]
            MainActor.assumeIsolated {
                guard let action = info["action"] as? String else { return dump(store: store, ui: ui) }
                perform(action, info)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { MainActor.assumeIsolated { dump(store: store, ui: ui) } }
            }
        }
    }

    /// In-process input so tests work even when the screen is locked.
    /// click/rclick/dblclick: "window" index + "x","y" in screenshot coordinates (top-left origin).
    /// key: "chars" + optional "keyCode" and "mods" ("cmd,shift").
    private static var lastHit = ""
    private static var axDump: [String] = []
    private static var reminders: ReminderScheduler?
    private static var probeStore: Store?
    private static var probeUI: UIState?
    private static var popoverWindow: NSWindow?
    private static var pickerWindow: NSWindow?
    private static var lastMenu: NSMenu?

    private static func perform(_ action: String, _ info: [AnyHashable: Any]) {
        if action == "popover" {
            // The real MenuBarExtra window can't open while the app can't activate; host the same view.
            guard let store = probeStore, let ui = probeUI, let reminders else { return }
            let host = NSHostingView(rootView: PopoverView().environment(store).environment(ui).environment(reminders).environment(Updater()))
            let win = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 340, height: 440), styleMask: [.titled], backing: .buffered, defer: false)
            win.title = "Popover preview"
            win.contentView = host
            win.orderFront(nil)
            popoverWindow = win
            lastHit = "popover preview opened"
            return
        }
        if action == "picker" {
            // Host the reminder picker in its own window for a snapshot.
            let win = NSWindow(contentRect: NSRect(x: 600, y: 200, width: 300, height: 560), styleMask: [.titled], backing: .buffered, defer: false)
            win.title = "Picker preview"
            win.contentView = NSHostingView(rootView: ReminderPicker(current: nil) { _ in })
            win.setContentSize(win.contentView!.fittingSize)
            win.orderFront(nil)
            pickerWindow = win
            return
        }
        if action == "expand" || action == "note" {
            // State shortcuts for layout checks: expand a task / set its notes (by title).
            guard let store = probeStore, let ui = probeUI,
                  let task = store.data.tasks.first(where: { $0.title == info["title"] as? String }) else { lastHit = "no task"; return }
            if action == "expand" { ui.toggleExpanded(task.id) } else { store.setNotes(task.id, info["text"] as? String ?? "") }
            lastHit = "\(action) \(task.title)"
            return
        }
        if action == "colorPanel" {
            // Pick a color in the open system color panel, like a user would.
            let hex = UInt32((info["hex"] as? String ?? "FF2D55"), radix: 16) ?? 0
            let panel = NSColorPanel.shared
            panel.color = .hex(hex)
            ColorPanelBridge.active?.colorChanged(panel)   // as a user pick does
            lastHit = "color panel visible=\(NSColorPanel.shared.isVisible)"
            return
        }
        if action == "statusInfo" || action == "statusSend" {
            let button = NSApp.windows.filter { "\(type(of: $0))" == "NSStatusBarWindow" && $0.isVisible }
                .compactMap { allSubviews($0.contentView).first { $0 is NSStatusBarButton } as? NSStatusBarButton }.first
            if action == "statusSend", let b = button, let a = b.action { NSApp.sendAction(a, to: b.target, from: b) }
            lastHit = "button=\(button != nil) action=\(button?.action.map(NSStringFromSelector) ?? "nil") target=\(button?.target.map { "\(type(of: $0))" } ?? "nil") menu=\(button?.menu != nil)"
            return
        }
        if action == "status" {
            // Click the menu bar icon to toggle the popover.
            let button = NSApp.windows.filter { "\(type(of: $0))" == "NSStatusBarWindow" && $0.isVisible }
                .compactMap { allSubviews($0.contentView).first { $0 is NSStatusBarButton } as? NSStatusBarButton }.first
            button?.performClick(nil)
            lastHit = button == nil ? "no status button" : "status clicked"
            return
        }
        let idx = Int(info["window"] as? String ?? "1") ?? 1
        guard NSApp.windows.indices.contains(idx) else { return }
        let w = NSApp.windows[idx]
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.makeKey()
        let height = w.contentView?.superview?.bounds.height ?? w.frame.height
        let x = Double(info["x"] as? String ?? "0") ?? 0, y = Double(info["y"] as? String ?? "0") ?? 0
        let p = NSPoint(x: x, y: height - y)
        let t = ProcessInfo.processInfo.systemUptime
        func mouse(_ type: NSEvent.EventType, _ clicks: Int) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: t, windowNumber: w.windowNumber,
                               context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
        }
        switch action {
        case "click", "dblclick":
            // Through the window so SwiftUI gesture recognizers see it (needs an unlocked, active app).
            lastHit = w.contentView?.superview?.hitTest(p).map { "\(type(of: $0))" } ?? "nil"
            for n in action == "click" ? [1] : [1, 2] {
                NSApp.postEvent(mouse(.leftMouseUp, n), atStart: false)   // dequeued by the mouseDown tracking loop
                w.sendEvent(mouse(.leftMouseDown, n))
            }
        case "rclick":
            let target = w.contentView?.superview?.hitTest(p)
            lastHit = target.map { "\(type(of: $0))" } ?? "nil"
            var v = target
            lastMenu = nil
            while let view = v, lastMenu == nil { lastMenu = view.menu(for: mouse(.rightMouseDown, 1)); v = view.superview }
            lastMenu?.update()
        case "select":
            // Select a row of the Nth table view (0 = sidebar) like a click would.
            let tables = allTables(in: w.contentView)
            let t = Int(info["table"] as? String ?? "0") ?? 0, row = Int(info["row"] as? String ?? "0") ?? 0
            guard tables.indices.contains(t) else { lastHit = "no table \(t)"; break }
            tables[t].selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            lastHit = "selected row \(row) of table \(t)"
        case "type":
            // Focus the text field under the point, insert "text", optionally press Return.
            var v = w.contentView?.superview?.hitTest(p)
            while let view = v, !(view is NSTextField), !(view is NSTextView) { v = view.superview }
            if let textView = v as? NSTextView {   // multi-line editors (notes)
                w.makeFirstResponder(textView)
                textView.insertText(info["text"] as? String ?? "", replacementRange: textView.selectedRange())
                lastHit = "typed into \(type(of: textView))"
                break
            }
            guard let field = v as? NSTextField else { lastHit = "no text field"; break }
            w.makeFirstResponder(field)
            let editor = field.currentEditor() as? NSTextView
            editor?.insertText(info["text"] as? String ?? "", replacementRange: editor?.selectedRange() ?? NSRange())
            if info["submit"] as? String == "1" { editor?.insertNewline(nil) }
            lastHit = "typed into \(type(of: field))"
        case "popup":
            // SwiftUI Menu buttons are pop-up buttons: list their items, or fire "item".
            var v = w.contentView?.superview?.hitTest(p)
            while let view = v, !(view is NSPopUpButton) { v = view.superview }
            guard let button = v as? NSPopUpButton, let menu = button.menu else { lastHit = "no popup at point (\(v.map { "\(type(of: $0))" } ?? "nil"))"; break }
            menu.update()
            lastMenu = menu
            if let title = info["item"] as? String, let i = menu.items.firstIndex(where: { $0.title.contains(title) }) {
                menu.performActionForItem(at: i)
            }
            lastHit = "popup \(button.title)"
        case "axdump":
            // List accessible elements (role, label) so tests know what can be pressed.
            var out: [String] = []
            func walk(_ e: Any, _ depth: Int) {
                guard depth < 40, let el = e as? NSAccessibilityElementProtocol & NSObject else { return }
                let role = (el as? NSAccessibilityProtocol)?.accessibilityRole()?.rawValue ?? "?"
                let label = (el as? NSAccessibilityProtocol)?.accessibilityLabel() ?? ""
                let title = (el as? NSAccessibilityProtocol)?.accessibilityTitle() ?? ""
                let value = ((el as? NSAccessibilityProtocol)?.accessibilityValue()).map { "\($0)" } ?? ""
                if !(label.isEmpty && title.isEmpty && value.isEmpty) || role.contains("Button") {
                    out.append(String(repeating: " ", count: depth) + "\(role) l=\(label) t=\(title) v=\(value.prefix(40))")
                }
                for c in (el as? NSAccessibilityProtocol)?.accessibilityChildren() ?? [] { walk(c, depth + 1) }
            }
            for v in allSubviews(w.contentView) where "\(type(of: v))".contains("Hosting") { walk(v, 0) }
            axDump = out
        case "press":
            // Press the Nth (default 0) accessible element whose label/title contains "label".
            let needle = info["label"] as? String ?? ""
            let nth = Int(info["nth"] as? String ?? "0") ?? 0
            var found: [NSAccessibilityProtocol] = []
            func walk(_ e: Any, _ depth: Int) {
                guard depth < 40, let el = e as? NSAccessibilityProtocol else { return }
                let text = (el.accessibilityLabel() ?? "") + "|" + (el.accessibilityTitle() ?? "")
                if text.contains(needle), el.accessibilityRole() == .button || el.accessibilityRole() == .popUpButton || el.accessibilityRole() == .menuButton || el.accessibilityRole() == .checkBox { found.append(el) }
                for c in el.accessibilityChildren() ?? [] { walk(c, depth + 1) }
            }
            for v in allSubviews(w.contentView) where "\(type(of: v))".contains("Hosting") { walk(v, 0) }
            if found.indices.contains(nth) {
                let ok = found[nth].accessibilityPerformPress()
                lastHit = "pressed \(needle)#\(nth) of \(found.count) ok=\(ok)"
            } else { lastHit = "no button '\(needle)' (\(found.count) found)" }
        case "sidebarWidth":
            // Same as dragging the sidebar divider.
            let split = allSubviews(w.contentView).compactMap { $0 as? NSSplitView }.first
            split?.setPosition(CGFloat(Double(info["w"] as? String ?? "200") ?? 200), ofDividerAt: 0)
            lastHit = split == nil ? "no split view" : "sidebar width set"
        case "size":
            let width = Double(info["w"] as? String ?? "960") ?? 960, height = Double(info["h"] as? String ?? "620") ?? 620
            // Optional "screen" index puts the window on that screen (e.g. a Retina one for 2x snapshots).
            var origin = NSPoint(x: w.frame.minX, y: w.frame.maxY - height)
            if let i = Int(info["screen"] as? String ?? ""), NSScreen.screens.indices.contains(i) {
                let f = NSScreen.screens[i].visibleFrame
                origin = NSPoint(x: f.midX - width / 2, y: f.midY - height / 2)
            }
            w.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
            lastHit = "resized"
        case "menu":
            // "path" like "Move to/🏠 Home": walk the last context menu and fire the item.
            var menu = lastMenu
            let parts = (info["path"] as? String ?? "").split(separator: "/").map(String.init)
            for (i, title) in parts.enumerated() {
                guard let m = menu, let index = m.items.firstIndex(where: { $0.title == title }) else { lastHit = "no item \(title)"; break }
                if i == parts.count - 1 { m.performActionForItem(at: index) } else { menu = m.items[index].submenu; menu?.update() }
            }
        case "key":
            let chars = info["chars"] as? String ?? ""
            let code = UInt16(info["keyCode"] as? String ?? "0") ?? 0
            var flags: NSEvent.ModifierFlags = []
            for m in (info["mods"] as? String ?? "").split(separator: ",") {
                switch m { case "cmd": flags.insert(.command); case "shift": flags.insert(.shift); case "opt": flags.insert(.option); default: break }
            }
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: t, windowNumber: w.windowNumber,
                                         context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
                if type == .keyDown, flags.contains(.command), NSApp.mainMenu?.performKeyEquivalent(with: e) == true { continue }
                w.sendEvent(e)
            }
        default: break
        }
    }

    private static func allSubviews(_ view: NSView?) -> [NSView] {
        guard let view else { return [] }
        return [view] + view.subviews.flatMap { allSubviews($0) }
    }

    private static func allTables(in view: NSView?) -> [NSTableView] {
        guard let view else { return [] }
        return (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap { allTables(in: $0) }
    }

    private static func describe(_ m: NSMenu) -> [String] {
        m.items.flatMap { item -> [String] in
            let image = item.image.map { $0.isTemplate ? " [template img]" : " [color img]" } ?? ""
            let me = item.isSeparatorItem ? "---" : item.title + image + (item.state == .on ? " ✓" : "") + (item.isEnabled ? "" : " (disabled)")
            return [me] + (item.submenu.map { describe($0).map { "  " + $0 } } ?? [])
        }
    }

    private static func dump(store: Store, ui: UIState) {
        let dir = URL(fileURLWithPath: "/tmp/metodo-probe")
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var windows: [[String: Any]] = []
        for (i, w) in NSApp.windows.enumerated() where w.isVisible {
            let f = w.frame
            windows.append(["index": i, "title": w.title, "class": "\(type(of: w))", "id": w.identifier?.rawValue ?? "",
                            "frame": [f.origin.x, f.origin.y, f.width, f.height], "key": w.isKeyWindow])
            guard let view = w.contentView?.superview ?? w.contentView else { continue }
            // Always render at 2x so README screenshots stay sharp on 1x displays too.
            let b = view.bounds
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(b.width * 2), pixelsHigh: Int(b.height * 2),
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            rep.size = b.size
            view.cacheDisplay(in: b, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("window-\(i).png"))
        }
        let sidebar: String = switch ui.sidebar {
        case .today: "today"
        case .all: "all"
        case .completed: "completed"
        case .project(let id): "project:\(store.project(id)?.name ?? id.uuidString)"
        }
        let state: [String: Any] = [
            "sidebar": sidebar,
            "lastHit": lastHit,
            "ax": axDump,
            "tables": NSApp.windows.compactMap { $0.isVisible ? $0 : nil }.flatMap { allTables(in: $0.contentView) }.map {
                "\(type(of: $0)) rows=\($0.numberOfRows) selected=\($0.selectedRow) x=\(Int($0.convert($0.bounds, to: nil).minX))"
            },
            "lastMenu": lastMenu.map { describe($0) } ?? [],
            "selectedTask": ui.selectedTaskID.flatMap { store.task($0)?.title } ?? NSNull(),
            "popoverShowsAll": ui.popoverShowsAll,
            "activationPolicy": NSApp.activationPolicy().rawValue,
            "screenFrames": NSScreen.screens.map { [$0.frame.origin.x, $0.frame.origin.y, $0.frame.width, $0.frame.height, $0.backingScaleFactor] },
            "windows": windows,
            "projects": store.data.projects.map(\.displayName),
            "tasks": store.data.tasks.map { ["title": $0.title, "project": store.project($0.projectID)?.name ?? "?",
                                             "done": $0.isDone, "inToday": $0.inToday,
                                             "remindAt": $0.remindAt.map { Queries.reminderLabel($0, now: Date(), locale: Locale(identifier: "en_US")) } ?? ""] },
        ]
        if let json = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) {
            try? json.write(to: dir.appendingPathComponent("state.json"))
        }
    }
}
#endif
