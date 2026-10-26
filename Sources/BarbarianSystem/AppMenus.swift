import AppKit
import ApplicationServices

/// The frontmost app's menus at the left of the active menu bar, read
/// through the Accessibility API.
public enum AppMenus {
    /// How far the frontmost app's menus reach from the left edge of the
    /// active display, or nil without Accessibility permission.
    public static func width(onActiveDisplayAt displayMinX: CGFloat) -> CGFloat? {
        guard
            AccessibilityPermission.isGranted,
            let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        else {
            return nil
        }
        let app = AXUIElement.application(pid, timeout: 0.1)
        guard
            let menuBar: AXUIElement = app.attribute(kAXMenuBarAttribute),
            let menus: [AXUIElement] = menuBar.attribute(kAXChildrenAttribute)
        else {
            return nil
        }
        return menus.compactMap(\.frame?.maxX).max().map { $0 - displayMinX }
    }
}
