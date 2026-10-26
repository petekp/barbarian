import AppKit

/// A display with a menu bar, in window-list coordinates: origin at the top
/// left of the main display, y growing downward.
public struct MenuBarDisplay: Sendable, Equatable {
    public let bounds: CGRect
    /// The x range where status items can appear: right of the notch, when
    /// the display has one.
    public let statusArea: ClosedRange<CGFloat>
    public let menuBarHeight: CGFloat

    /// Every display with a menu bar. Without "Displays have separate
    /// Spaces", only the main display has one.
    public static var all: [MenuBarDisplay] {
        let screens = NSScreen.screensHaveSeparateSpaces ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
        return screens.compactMap(MenuBarDisplay.init)
    }

    /// The display whose menu bar holds a window with this frame. Given the
    /// frame of the window behind Barbarian's icon, which is the icon's own
    /// window and never a copy, this is the active menu bar. `NSScreen.main`
    /// is not a substitute: it can name another display.
    public static func holding(_ windowFrame: CGRect) -> MenuBarDisplay? {
        all.first { $0.bounds.minY == windowFrame.minY && $0.bounds.minX <= windowFrame.midX && windowFrame.midX <= $0.bounds.maxX }
    }

    /// The display whose menu bar contains `point`, if any.
    public static func withMenuBar(containing point: CGPoint) -> MenuBarDisplay? {
        all.first { $0.menuBarFrame.contains(point) }
    }

    public var menuBarFrame: CGRect {
        CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: menuBarHeight)
    }

    /// The pointer in window-list coordinates.
    public static var pointerLocation: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    /// A menu bar that hides until the pointer reaches the top of the screen
    /// reports no height while hidden.
    private static let minimumMenuBarHeight: CGFloat = 24

    init?(screen: NSScreen) {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }
        bounds = CGDisplayBounds(displayID)
        statusArea = (screen.auxiliaryTopRightArea?.minX ?? bounds.minX)...bounds.maxX
        menuBarHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, Self.minimumMenuBarHeight)
    }
}
