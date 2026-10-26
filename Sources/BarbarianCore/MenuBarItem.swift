import CoreGraphics

public typealias WindowID = UInt32

/// One status item window in the menu bar, as the window server reports it.
///
/// `frame` is in global display coordinates with the origin at the top left
/// of the main display, the convention Core Graphics window lists use.
public struct MenuBarItem: Hashable, Sendable, Identifiable {
    public let windowID: WindowID
    public let ownerPID: Int32
    public let ownerName: String
    /// The window title. The window server withholds titles of other apps'
    /// windows from processes without Screen Recording permission.
    public let title: String?
    public let frame: CGRect
    public let isOnScreen: Bool

    public var id: WindowID { windowID }

    public init(
        windowID: WindowID,
        ownerPID: Int32,
        ownerName: String,
        title: String?,
        frame: CGRect,
        isOnScreen: Bool
    ) {
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.title = title
        self.frame = frame
        self.isOnScreen = isOnScreen
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(windowID)
    }
}
