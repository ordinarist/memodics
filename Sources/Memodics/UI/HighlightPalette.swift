import AppKit
import SwiftUI

/// Maps highlight levels (SPEC §13) to progressively stronger colors.
///
/// Level 0 is transparent (no highlight — newly-understood or zero-count).
/// Higher levels move from a soft yellow toward a saturated orange/red so
/// frequently-encountered vocabulary is visibly stronger.
enum HighlightPalette {

    /// Background tint for the highlighted vocabulary in the original text.
    static func color(forLevel level: Int) -> NSColor {
        switch level {
        case 1: return NSColor.systemYellow.withAlphaComponent(0.25)
        case 2: return NSColor.systemYellow.withAlphaComponent(0.40)
        case 3: return NSColor.systemOrange.withAlphaComponent(0.40)
        case 4: return NSColor.systemOrange.withAlphaComponent(0.60)
        case 5: return NSColor.systemRed.withAlphaComponent(0.45)
        case 6: return NSColor.systemRed.withAlphaComponent(0.65)
        default: return .clear
        }
    }

    static func swiftUIColor(forLevel level: Int) -> Color {
        Color(nsColor: color(forLevel: level))
    }
}
