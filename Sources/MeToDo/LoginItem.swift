import Foundation
import AppKit
import ServiceManagement

enum LoginItem {
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }

    /// True when macOS started the app at login rather than the user opening it.
    /// Only meaningful during applicationDidFinishLaunching, while the launch event is current.
    static var launchedAtLogin: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent, event.eventID == kAEOpenApplication else { return false }
        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    /// Failures are logged only; the ⚙︎ toggle reads `isOn` and will simply show off (spec §11).
    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("MeToDo login item: \(error)")
        }
    }
}
