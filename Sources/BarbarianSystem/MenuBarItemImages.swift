import BarbarianCore
import ScreenCaptureKit
import Synchronization

/// Captures menu bar items' own images with ScreenCaptureKit. Needs Screen
/// Recording permission.
public enum MenuBarItemImages {
    /// Pixels per point in captured images.
    public static let scale: CGFloat = 2

    /// Images of the on-screen items among `items`, keyed by window ID.
    ///
    /// A capture of an off-screen item's window never finishes, so those are
    /// skipped, and a capture that has not finished in a second is dropped in
    /// case its item went off screen meanwhile.
    public static func capture(_ items: [MenuBarItem]) async -> [WindowID: CGImage] {
        let wanted = Set(items.filter(\.isOnScreen).map(\.windowID))
        guard
            ScreenRecordingPermission.isGranted,
            !wanted.isEmpty,
            let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        else {
            return [:]
        }
        var images: [WindowID: CGImage] = [:]
        for window in content.windows where wanted.contains(window.windowID) {
            images[window.windowID] = await image(of: window)
        }
        return images
    }

    private static let captureTimeout: Duration = .seconds(1)

    private static func image(of window: SCWindow) async -> CGImage? {
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width * scale)
        configuration.height = Int(window.frame.height * scale)
        configuration.showsCursor = false
        let filter = SCContentFilter(desktopIndependentWindow: window)

        return await withCheckedContinuation { continuation in
            let resumed = Mutex(false)
            let finish: @Sendable (CGImage?) -> Void = { image in
                let isFirst = resumed.withLock { wasResumed in
                    defer { wasResumed = true }
                    return !wasResumed
                }
                if isFirst { continuation.resume(returning: image) }
            }
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, _ in
                finish(image)
            }
            Task {
                try? await Task.sleep(for: captureTimeout)
                finish(nil)
            }
        }
    }
}
