import BarbarianCore
import ScreenCaptureKit
import Synchronization

/// Captures menu bar items' own images with ScreenCaptureKit. Needs Screen
/// Recording permission.
///
/// Each capture request can make macOS show its screen recording alert, so a
/// round of items is one request: one picture of the stretch of menu bar that
/// holds them, cut into each item's image. Rounds never overlap.
public enum MenuBarItemImages {
    /// Pixels per point in captured images.
    public static let scale: CGFloat = 2

    private static var isCapturing = false

    /// Images of the on-screen items among `items`, keyed by window ID. Empty
    /// while an earlier round is under way.
    public static func capture(_ items: [MenuBarItem]) async -> [WindowID: CGImage] {
        let onScreen = items.filter(\.isOnScreen)
        guard ScreenRecordingPermission.isGranted, !isCapturing, let first = onScreen.first else { return [:] }
        isCapturing = true
        defer { isCapturing = false }
        guard
            let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
            let display = content.displays.first(where: { $0.frame.contains(CGPoint(x: first.frame.midX, y: first.frame.midY)) })
        else {
            return [:]
        }
        let onDisplay = onScreen.filter { display.frame.intersects($0.frame) }
        let ids = Set(onDisplay.map(\.windowID))
        let others = content.windows.filter { !ids.contains($0.windowID) }
        let area = onDisplay.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        guard let picture = await image(of: display, excluding: others, in: area) else { return [:] }

        return Dictionary(uniqueKeysWithValues: onDisplay.compactMap { item in
            let cut = CGRect(
                x: (item.frame.minX - area.minX) * scale,
                y: (item.frame.minY - area.minY) * scale,
                width: item.frame.width * scale,
                height: item.frame.height * scale
            )
            return picture.cropping(to: cut).map { (item.windowID, $0) }
        })
    }

    /// How long a round waits for macOS, which stops answering capture
    /// requests when its screen capture service is stuck.
    private static let captureTimeout: Duration = .seconds(3)

    /// `area`, in global coordinates, of `display` without `others`. Leaving
    /// out every other window leaves the items on a clear background. A
    /// filter that includes the items' windows instead captures nothing.
    private static func image(of display: SCDisplay, excluding others: [SCWindow], in area: CGRect) async -> CGImage? {
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = area.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        configuration.width = Int(area.width * scale)
        configuration.height = Int(area.height * scale)
        configuration.showsCursor = false
        let filter = SCContentFilter(display: display, excludingWindows: others)

        return await withCheckedContinuation { continuation in
            let resumed = Mutex(false)
            let finish: @Sendable (CGImage?) -> Void = { image in
                let isFirst = resumed.withLock { wasResumed in
                    defer { wasResumed = true }
                    return !wasResumed
                }
                if isFirst { continuation.resume(returning: image) }
            }
            let timeout = Task {
                try? await Task.sleep(for: captureTimeout)
                finish(nil)
            }
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, _ in
                timeout.cancel()
                finish(image)
            }
        }
    }
}
