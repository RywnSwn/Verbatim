import AppKit
import SwiftUI

/// The "Notebook" look Ryan picked in step 2b: warm white paper, ink text,
/// transcript in Apple's New York serif, controls in the normal Mac font.
/// No bright colors: the main button is ink, links are a dark ink blue.
enum Theme {
    /// Main area background: a touch warmer than pure white.
    static let paper = dynamic(light: 0xFCFBF8, dark: 0x1D1C1A)
    /// Text.
    static let ink = dynamic(light: 0x1F1D1A, dark: 0xEBE8E1)
    /// Thin divider lines.
    static let line = dynamic(light: 0xE6E2DA, dark: 0x34322E)
    /// Links, focus and the edit underline.
    static let accent = dynamic(light: 0x24427A, dark: 0x8FA9DD)

    /// Search hits, and the current hit (stronger).
    static let highlight = dynamic(light: 0xFBE9A6, dark: 0x5C4B16)
    static let highlightCurrent = dynamic(light: 0xF2C230, dark: 0x9A7514)

    /// Transcript text: serif, a bit bigger than normal text so it reads like notes.
    static let transcript = Font.system(size: 17, design: .serif)
    static let transcriptLineSpacing: CGFloat = 5
    /// Space between transcript lines.
    static let lineGap: CGFloat = 14

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return rgb(isDark ? dark : light)
        })
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// The one main button on a screen (Copy all, Start recording): filled with
/// ink, text in paper color. Flips to light ink in dark mode.
struct InkButtonStyle: ButtonStyle {
    var large = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(large ? .body.weight(.medium) : .callout.weight(.medium))
            .foregroundStyle(Theme.paper)
            .padding(.horizontal, large ? 20 : 12)
            .padding(.vertical, large ? 9 : 5)
            .background(Theme.ink.opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == InkButtonStyle {
    static var ink: InkButtonStyle { InkButtonStyle() }
    static var inkLarge: InkButtonStyle { InkButtonStyle(large: true) }
}
