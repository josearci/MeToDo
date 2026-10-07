import SwiftUI
import AppKit
import MeToDoCore

enum MenuBarIcon {
    /// Template checkmark normally; with a red dot while anything is overdue (spec §5).
    static func image(overdue: Bool) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let symbol = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "MeToDo")!
            .withSymbolConfiguration(config)!
        guard overdue else {
            symbol.isTemplate = true
            return symbol
        }
        let size = symbol.size
        // The drawing handler runs at draw time with the menu bar's appearance, so labelColor
        // matches light/dark menu bars even though the image isn't a template.
        let image = NSImage(size: size, flipped: false) { rect in
            symbol.draw(in: rect)
            NSColor.labelColor.set()
            rect.fill(using: .sourceAtop)
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.maxX - 6, y: rect.maxY - 6, width: 6, height: 6)).fill()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "MeToDo, overdue tasks"
        return image
    }
}
