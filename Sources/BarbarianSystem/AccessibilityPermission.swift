import AppKit
import ApplicationServices

/// Accessibility permission, which macOS requires before an app can post
/// mouse events to other apps' menu bar items.
public enum AccessibilityPermission {
    public static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt that offers to open the Accessibility list.
    public static func request() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    public static func requestAndOpenSettings() {
        request()
        openSettings()
    }
}
