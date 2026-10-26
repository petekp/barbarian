/// Where to drop a menu bar item relative to another one.
public enum MoveDestination: Hashable, Sendable {
    case leftOf(WindowID)
    case rightOf(WindowID)
}
