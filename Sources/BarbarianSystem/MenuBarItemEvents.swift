import AppKit
import BarbarianCore

public enum MenuBarItemEventError: Error, CustomStringConvertible {
    case accessibilityNotGranted
    case itemGone(WindowID)
    case modifierKeysHeld
    case moveDidNotLand(WindowID)

    public var description: String {
        switch self {
        case .accessibilityNotGranted: "Barbarian needs Accessibility permission to move or click menu bar items."
        case .itemGone(let id): "Menu bar item \(id) no longer exists."
        case .modifierKeysHeld: "A modifier key is held down. Release it and try again."
        case .moveDidNotLand(let id): "Menu bar item \(id) did not move."
        }
    }
}

/// Moves and clicks other apps' menu bar items by posting mouse events
/// addressed to the item's window.
///
/// macOS has no API for this. A Command-mouse-down on an item followed by a
/// mouse-up over another item is the system's own drag-to-rearrange gesture.
/// Setting the window fields delivers the events to the item even when it is
/// off screen. Every call checks Accessibility permission first, because
/// macOS drops posted events from untrusted processes.
public enum MenuBarItemEvents {
    /// Moves `item` next to `target` and waits for its frame to change.
    public static func move(_ item: WindowID, ownerPID: Int32, to destination: MoveDestination) async throws {
        guard AccessibilityPermission.isGranted else { throw MenuBarItemEventError.accessibilityNotGranted }
        try await waitForModifierKeysReleased()
        guard let startFrame = MenuBarWindowList.frame(of: item) else { throw MenuBarItemEventError.itemGone(item) }

        let (targetID, endPoint) = try endPoint(for: destination)
        let offscreenStart = CGPoint(x: 20_000, y: 20_000)

        try await withCursorParked {
            for attempt in 1...maximumAttempts {
                postToSessionAndOwner(mouseEvent(.leftMouseDown, at: offscreenStart, window: item, pid: ownerPID, flags: .maskCommand), ownerPID: ownerPID)
                try await Task.sleep(for: eventGap)
                postToSessionAndOwner(mouseEvent(.leftMouseUp, at: endPoint, window: targetID, pid: ownerPID, flags: []), ownerPID: ownerPID)
                if await waitForFrameChange(of: item, from: startFrame) { return }
                if attempt == maximumAttempts { throw MenuBarItemEventError.moveDidNotLand(item) }
            }
        }
    }

    /// Clicks `item` the way a left click on it would.
    public static func click(_ item: WindowID, ownerPID: Int32) async throws {
        guard AccessibilityPermission.isGranted else { throw MenuBarItemEventError.accessibilityNotGranted }
        guard let frame = MenuBarWindowList.frame(of: item) else { throw MenuBarItemEventError.itemGone(item) }
        let point = CGPoint(x: frame.midX, y: frame.midY)
        try await withCursorParked {
            mouseEvent(.leftMouseDown, at: point, window: item, pid: ownerPID, flags: [], clickState: 1)?.post(tap: .cgSessionEventTap)
            try await Task.sleep(for: eventGap)
            mouseEvent(.leftMouseUp, at: point, window: item, pid: ownerPID, flags: [], clickState: 1)?.post(tap: .cgSessionEventTap)
        }
    }

    private static let maximumAttempts = 3
    private static let eventGap = Duration.milliseconds(40)
    private static let frameChangeTimeout = Duration.milliseconds(400)

    /// The window field Core Graphics does not name. Ice and similar menu bar
    /// managers set it alongside the two documented window fields.
    private static let windowIDField = CGEventField(rawValue: 0x33)!

    private static func endPoint(for destination: MoveDestination) throws -> (WindowID, CGPoint) {
        switch destination {
        case .leftOf(let target):
            guard let frame = MenuBarWindowList.frame(of: target) else { throw MenuBarItemEventError.itemGone(target) }
            return (target, CGPoint(x: frame.minX, y: frame.midY))
        case .rightOf(let target):
            guard let frame = MenuBarWindowList.frame(of: target) else { throw MenuBarItemEventError.itemGone(target) }
            return (target, CGPoint(x: frame.maxX, y: frame.midY))
        }
    }

    private static func mouseEvent(
        _ type: CGEventType,
        at location: CGPoint,
        window: WindowID,
        pid: Int32,
        flags: CGEventFlags,
        clickState: Int64? = nil
    ) -> CGEvent? {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: .left) else {
            return nil
        }
        event.flags = flags
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window))
        event.setIntegerValueField(windowIDField, value: Int64(window))
        if let clickState { event.setIntegerValueField(.mouseEventClickState, value: clickState) }
        return event
    }

    /// Moves are delivered to both the session and the owning app, as Ice
    /// does. Clicks go to the session only, so the item sees one click.
    private static func postToSessionAndOwner(_ event: CGEvent?, ownerPID pid: Int32) {
        guard let event else { return }
        event.post(tap: .cgSessionEventTap)
        event.postToPid(pid)
    }

    private static func waitForFrameChange(of item: WindowID, from startFrame: CGRect) async -> Bool {
        let deadline = ContinuousClock.now + frameChangeTimeout
        while ContinuousClock.now < deadline {
            if let frame = MenuBarWindowList.frame(of: item), frame != startFrame { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    private static func waitForModifierKeysReleased() async throws {
        let modifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        for _ in 0..<50 {
            if CGEventSource.flagsState(.combinedSessionState).isDisjoint(with: modifiers) { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw MenuBarItemEventError.modifierKeysHeld
    }

    /// Hides the pointer while events fly, then puts it back where it was.
    /// Posting a mouse event moves the real pointer to the event's location.
    private static func withCursorParked(_ body: () async throws -> Void) async throws {
        let cursorLocation = CGEvent(source: nil)?.location ?? .zero
        CGDisplayHideCursor(CGMainDisplayID())
        defer {
            CGWarpMouseCursorPosition(cursorLocation)
            CGAssociateMouseAndMouseCursorPosition(1)
            CGDisplayShowCursor(CGMainDisplayID())
        }
        try await body()
    }
}
