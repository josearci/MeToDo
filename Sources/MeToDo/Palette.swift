import SwiftUI
import AppKit
import MeToDoCore

extension ProjectColor {
    private var hex: (dark: UInt32, light: UInt32) {
        switch self {
        case .gray: (0x9A9AA0, 0x8A8A8F)
        case .red: (0xFF6B6B, 0xD93B3B)
        case .orange: (0xFF9F45, 0xC96A12)
        case .yellow: (0xF5C451, 0xC08A12)
        case .green: (0x4CC38A, 0x1F9D63)
        case .teal: (0x4CC9D0, 0x13838A)
        case .blue: (0x5AA9FF, 0x2E6FD1)
        case .purple: (0xA78BFA, 0x7C5CD6)
        }
    }

    /// Full project color: checkboxes, headers, rails, dots.
    var color: Color {
        let hex = hex
        return Color(nsColor: NSColor(name: nil) { $0.isDark ? .hex(hex.dark) : .hex(hex.light) })
    }

    /// Task titles: the project color softened toward the text color (58% dark, 72% light).
    var titleColor: Color {
        let hex = hex
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isDark
                ? NSColor.hex(hex.dark).blended(withFraction: 0.42, of: .hex(0xF2F2F4))!
                : NSColor.hex(hex.light).blended(withFraction: 0.28, of: .hex(0x1D1D1F))!
        })
    }
}

extension NSColor {
    static func hex(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}
