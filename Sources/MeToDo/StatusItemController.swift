import AppKit
import SwiftUI
import Carbon.HIToolbox
import MeToDoCore

/// The menu bar icon and its popover panel. AppKit instead of SwiftUI's MenuBarExtra because
/// MenuBarExtra can't be opened from code, and the global hotkey needs to open it.
@MainActor
final class StatusItemController: NSObject, NSWindowDelegate {
    static let hotKeyDescription = "⌃⌥M"

    private let store: Store
    private let ui: UIState
    private let reminders: ReminderScheduler
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var panel: NSPanel?
    private var hotKey: HotKey?
    private(set) var hotKeyRegistered = false

    init(store: Store, ui: UIState, reminders: ReminderScheduler) {
        self.store = store
        self.ui = ui
        self.reminders = reminders
        super.init()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)
        refreshIcon()
        // The menu bar icon is always on screen, so a zero-size SwiftUI view inside it can hand
        // SwiftUI's open-window action to AppKit code (first launch, notifications, ⌘N).
        if let button = statusItem.button {
            let relay = NSHostingView(rootView: OpenWindowRelay(ui: ui))
            relay.frame = .zero
            button.addSubview(relay)
        }
        // ⌃⌥M from anywhere. A registered hotkey only ever receives this exact combination.
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            self?.toggle()
        }
        hotKeyRegistered = hotKey != nil
    }

    /// Red dot while something is overdue.
    func refreshIcon() {
        statusItem.button?.image = MenuBarIcon.image(overdue: Queries.anyOverdue(store.data, now: ui.now))
    }

    var isShown: Bool { panel?.isVisible == true }

    @objc func toggle() {
        isShown ? close() : show()
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 440),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.close() }

        let background = NSVisualEffectView(frame: panel.contentRect(forFrameRect: panel.frame))
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        let host = NSHostingView(rootView: PopoverView()
            .environment(store)
            .environment(ui)
            .environment(reminders))
        host.frame = background.bounds
        host.autoresizingMask = [.width, .height]
        background.addSubview(host)
        panel.contentView = background
        return panel
    }

    /// Centered under the menu bar icon, kept on screen.
    private func position(_ panel: NSPanel) {
        guard let buttonWindow = statusItem.button?.window else { return }
        let icon = buttonWindow.frame
        let screen = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var origin = NSPoint(x: icon.midX - panel.frame.width / 2, y: icon.minY - panel.frame.height - 4)
        origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - panel.frame.width - 8)
        panel.setFrameOrigin(origin)
    }

    // Click outside or switch apps → close, like a menu.
    func windowDidResignKey(_ notification: Notification) { close() }
}

/// Borderless panels can't become key by default, and the popover needs typing (Add field, notes).
private final class KeyablePanel: NSPanel {
    var onEscape: () -> Void = {}
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape() }
}

/// A system-wide hotkey through the Carbon hotkey service: no accessibility permission, and the
/// app is only told about its own combination; every other keystroke is untouched.
final class HotKey {
    private var ref: EventHotKeyRef?
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var installed = false

    init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        Self.installHandlerOnce()
        let id = Self.nextID
        Self.nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x4D54_444F), id: id)   // 'MTDO'
        guard RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr else {
            NSLog("MeToDo: hotkey already taken by another app")
            return nil
        }
        Self.handlers[id] = handler
    }

    deinit { if let ref { UnregisterEventHotKey(ref) } }

    private static func installHandlerOnce() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            DispatchQueue.main.async { HotKey.handlers[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

private struct OpenWindowRelay: View {
    let ui: UIState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                ui.openWindowAction = openWindow
                if ui.pendingOpenMain {
                    ui.pendingOpenMain = false
                    ui.openMainWindow()
                }
            }
    }
}
