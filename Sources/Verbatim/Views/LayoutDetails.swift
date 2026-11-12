import AppKit

/// Help > Copy Layout Details. Ryan can't see why something is in the wrong
/// place and Claude can't see his screen, so this copies the real numbers:
/// the window, the screen, and every view down a few levels with its frame.
@MainActor
enum LayoutDetails {
    static func copy() {
        let text = report()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        FileHandle.standardError.write(Data((text + "\n").utf8))
        RecorderModel.shared.show("Layout details copied. Paste them to Claude.")
    }

    static func report() -> String {
        var out = ["Verbatim \(AppInfo.version), macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"]
        for window in NSApp.windows where window.isVisible {
            out.append("")
            out.append("WINDOW \(window.identifier?.rawValue ?? "?") class=\(type(of: window))")
            out.append("  frame=\(r(window.frame)) contentLayoutRect=\(r(window.contentLayoutRect))")
            out.append("  minSize=\(s(window.minSize)) contentMinSize=\(s(window.contentMinSize)) maxSize=\(s(window.maxSize))")
            out.append("  styleMask=\(window.styleMask.rawValue) toolbarStyle=\(window.toolbarStyle.rawValue) titlebarTransparent=\(window.titlebarAppearsTransparent) fullScreen=\(window.styleMask.contains(.fullScreen)) zoomed=\(window.isZoomed)")
            if let screen = window.screen {
                out.append("  screen frame=\(r(screen.frame)) visible=\(r(screen.visibleFrame)) scale=\(screen.backingScaleFactor)")
            }
            if let content = window.contentView {
                out.append("  safeAreaInsets top=\(n(content.safeAreaInsets.top)) left=\(n(content.safeAreaInsets.left)) bottom=\(n(content.safeAreaInsets.bottom)) right=\(n(content.safeAreaInsets.right))")
                walk(content, depth: 0, into: &out)
            }
        }
        return out.joined(separator: "\n")
    }

    /// Frames are in window coordinates (y counts up from the window's bottom).
    private static func walk(_ view: NSView, depth: Int, into out: inout [String]) {
        guard depth <= 9, out.count < 260 else { return }
        let name = String(describing: type(of: view))
        let inWindow = view.convert(view.bounds, to: nil)
        var line = String(repeating: "  ", count: depth + 1) + "\(name) \(r(inWindow))"
        if view.isHidden { line += " hidden" }
        if let scroll = view as? NSScrollView {
            line += " scroll contentInsets top=\(n(scroll.contentInsets.top)) bottom=\(n(scroll.contentInsets.bottom)) offsetY=\(n(scroll.contentView.bounds.origin.y)) docH=\(n(scroll.documentView?.frame.height ?? 0))"
        }
        let insets = view.safeAreaInsets
        if insets.top != 0 || insets.bottom != 0 { line += " safe top=\(n(insets.top)) bottom=\(n(insets.bottom))" }
        out.append(line)
        // Rows and text inside lists are noise; the containers are what matter.
        if name.contains("TableRow") || name.contains("TextField") { return }
        for sub in view.subviews { walk(sub, depth: depth + 1, into: &out) }
    }

    private static func n(_ v: CGFloat) -> String { String(format: "%.0f", v) }
    private static func s(_ v: NSSize) -> String { "\(n(v.width))x\(n(v.height))" }
    private static func r(_ v: NSRect) -> String { "x\(n(v.minX)) y\(n(v.minY)) w\(n(v.width)) h\(n(v.height))" }
}
