import AppKit
import SwiftUI

extension NSWindow {
    /// A centered window showing `view`, kept when closed so it can open
    /// again.
    static func hosting<Content: View>(_ view: Content, title: String, size: NSSize, styleMask: NSWindow.StyleMask) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: styleMask, backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.center()
        return window
    }

    /// Activates Barbarian and brings the window forward. macOS can refuse
    /// activation to a background app, as when a terminal command opens a
    /// window, and the window still comes forward.
    func bringForward() {
        NSApp.activate()
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }
}
