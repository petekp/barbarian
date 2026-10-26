import AppKit
import CoreGraphics

/// Screen Recording permission, which macOS requires before an app can
/// capture other apps' menu bar items or read their window titles.
public enum ScreenRecordingPermission {
    public static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Shows the system prompt the first time. Later calls do nothing.
    public static func request() {
        CGRequestScreenCaptureAccess()
    }

    public static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}
