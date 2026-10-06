#if DEBUG
import AppKit
import MeToDoCore

/// Debug builds only: lets an outside test script see the app without screen-recording permission.
/// `METODO_DATA=/path/data.json` points the app at test data; posting the distributed notification
/// "com.josearci.metodo.probe" writes a PNG of every visible window plus state.json to /tmp/metodo-probe/.
@MainActor
enum DebugProbe {
    static var dataURL: URL? {
        ProcessInfo.processInfo.environment["METODO_DATA"].map { URL(fileURLWithPath: $0) }
    }

    static func install(store: Store, ui: UIState) {
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
    private static var lastMenu: NSMenu?

    private static func perform(_ action: String, _ info: [AnyHashable: Any]) {
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
            // Straight to the view under the point: the window's first-mouse filter would drop
            // clicks while the app can't activate (e.g. the screen is locked).
            let target = w.contentView?.superview?.hitTest(p)
            lastHit = target.map { "\(type(of: $0))" } ?? "nil"
            for n in action == "click" ? [1] : [1, 2] {
                NSApp.postEvent(mouse(.leftMouseUp, n), atStart: false)   // dequeued by the mouseDown tracking loop
                target?.mouseDown(with: mouse(.leftMouseDown, n))
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

    private static func allTables(in view: NSView?) -> [NSTableView] {
        guard let view else { return [] }
        return (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap { allTables(in: $0) }
    }

    private static func describe(_ m: NSMenu) -> [String] {
        m.items.flatMap { item -> [String] in
            let me = item.isSeparatorItem ? "---" : item.title + (item.isEnabled ? "" : " (disabled)")
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
            windows.append(["index": i, "title": w.title, "class": "\(type(of: w))",
                            "frame": [f.origin.x, f.origin.y, f.width, f.height], "key": w.isKeyWindow])
            guard let view = w.contentView?.superview ?? w.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("window-\(i).png"))
        }
        let sidebar: String = switch ui.sidebar {
        case .today: "today"
        case .all: "all"
        case .project(let id): "project:\(store.project(id)?.name ?? id.uuidString)"
        }
        let state: [String: Any] = [
            "sidebar": sidebar,
            "lastHit": lastHit,
            "tables": NSApp.windows.compactMap { $0.isVisible ? $0 : nil }.flatMap { allTables(in: $0.contentView) }.map {
                "\(type(of: $0)) rows=\($0.numberOfRows) selected=\($0.selectedRow) x=\(Int($0.convert($0.bounds, to: nil).minX))"
            },
            "lastMenu": lastMenu.map { describe($0) } ?? [],
            "selectedTask": ui.selectedTaskID.flatMap { store.task($0)?.title } ?? NSNull(),
            "popoverShowsAll": ui.popoverShowsAll,
            "activationPolicy": NSApp.activationPolicy().rawValue,
            "screenFrames": NSScreen.screens.map { [$0.frame.origin.x, $0.frame.origin.y, $0.frame.width, $0.frame.height] },
            "windows": windows,
            "projects": store.data.projects.map(\.displayName),
            "tasks": store.data.tasks.map { ["title": $0.title, "project": store.project($0.projectID)?.name ?? "?",
                                             "done": $0.isDone, "inToday": $0.inToday] },
        ]
        if let json = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) {
            try? json.write(to: dir.appendingPathComponent("state.json"))
        }
    }
}
#endif
