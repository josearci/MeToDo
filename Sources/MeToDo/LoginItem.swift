import Foundation
import ServiceManagement

enum LoginItem {
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }

    /// Failures are logged only; the ⚙︎ toggle reads `isOn` and will simply show off (spec §11).
    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("MeToDo login item: \(error)")
        }
    }
}
