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

    /// Design pass: a "paper card" row in the sidebar, and the solid sidebar.
    static let card = dynamic(light: 0xFFFFFF, dark: 0x2D2C29)
    static let sidebarSolid = dynamic(light: 0xF1EEE7, dark: 0x252421)

    /// Search hits, and the current hit (stronger).
    static let highlight = dynamic(light: 0xFBE9A6, dark: 0x5C4B16)
    static let highlightCurrent = dynamic(light: 0xF2C230, dark: 0x9A7514)

    /// Soft icon colors for groups (step 10). Muted so they sit with the ink.
    static let iconBlue = dynamic(light: 0x3F64A8, dark: 0x8FA9DD)
    static let iconGreen = dynamic(light: 0x4E7A52, dark: 0x8DB892)
    static let iconRed = dynamic(light: 0xA5503F, dark: 0xD99282)
    static let iconAmber = dynamic(light: 0xA97A22, dark: 0xD6B060)
    static let iconPurple = dynamic(light: 0x6E5A9C, dark: 0xB3A2D9)

    /// Transcript text: serif, a bit bigger than normal text so it reads like notes.
    /// Size comes from Settings or ⌘+ / ⌘− (step 10), see `TextSize`.
    static func transcript(_ size: Double) -> Font { Font.system(size: size, design: .serif) }
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

/// Transcript text size (step 10): ⌘+ / ⌘− / ⌘0, and the slider in Settings.
/// Only the transcript changes, not buttons or menus.
enum TextSize {
    static let key = "transcriptTextSize"
    static let normal: Double = 17
    static let range: ClosedRange<Double> = 13...26

    static var current: Double {
        let v = UserDefaults.standard.double(forKey: key)
        return v == 0 ? normal : v
    }

    static func change(by step: Double) {
        set(current + step)
    }

    static func set(_ value: Double) {
        UserDefaults.standard.set(min(max(value, range.lowerBound), range.upperBound), forKey: key)
    }
}

/// Settings > Look (design pass): the sidebar is glass (desktop shows through,
/// blurred) or a solid sheet. Reduce transparency always means solid.
enum SidebarLook: String {
    case glass, solid
    static let key = "sidebarLook"
}

/// Settings > Look (design pass): how each recording sits in the sidebar.
/// Soft boxes: a light ink tint. Paper cards: white cards, the open one ink.
enum RowLook: String {
    case soft, cards
    static let key = "rowLook"
}
