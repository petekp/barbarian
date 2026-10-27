import CoreGraphics

/// The window IDs of Barbarian's own status items.
public struct ControlItemIDs: Sendable, Equatable {
    public let icon: WindowID
    public let hiddenDivider: WindowID
    public let alwaysHiddenDivider: WindowID

    public init(icon: WindowID, hiddenDivider: WindowID, alwaysHiddenDivider: WindowID) {
        self.icon = icon
        self.hiddenDivider = hiddenDivider
        self.alwaysHiddenDivider = alwaysHiddenDivider
    }

    var dividers: Set<WindowID> { [hiddenDivider, alwaysHiddenDivider] }
}

/// Barbarian's reading of the menu bar at one moment: which managed item
/// sits where, and in which section.
public struct MenuBarLayout: Sendable, Equatable {
    public enum Entry: Hashable, Sendable, Identifiable {
        case item(MenuBarItem)
        case divider(Divider, WindowID)

        public var item: MenuBarItem? {
            if case .item(let item) = self { item } else { nil }
        }

        public var id: WindowID {
            switch self {
            case .item(let item): item.windowID
            case .divider(_, let id): id
            }
        }
    }

    /// Managed items and both dividers, left to right. Everything here sits
    /// left of Barbarian's icon.
    public let entries: [Entry]

    /// Managed items macOS gives no position, because they do not fit in
    /// the menu bar.
    public let unplacedItems: [MenuBarItem]

    public let controls: ControlItemIDs

    /// Items right of Barbarian's icon, left to right. They belong to macOS
    /// and are not managed.
    public let systemItems: [MenuBarItem]

    /// Managed items off screen because their app is not drawing them, as
    /// Now Playing is when nothing plays, rather than because they do not
    /// fit. Their frames are stale.
    ///
    /// macOS drops items that do not fit from the left end of the bar, so
    /// they sit left of every drawn item. An item its app is not drawing keeps
    /// its last frame, inside the visible bar and right of a drawn item.
    public let notDrawnItems: Set<WindowID>

    /// Reads a layout from one menu bar's items. `statusArea` is the x range
    /// where status items can appear in that menu bar.
    ///
    /// Divider roles follow position, not identity: the left divider always
    /// separates Always Hidden from Hidden. That keeps the sections in order
    /// when someone drags one divider past the other.
    public init?(items: [MenuBarItem], controls: ControlItemIDs, statusArea: ClosedRange<CGFloat>) {
        guard let icon = items.first(where: { $0.windowID == controls.icon }) else { return nil }
        self.controls = controls

        let placed = items.filter { $0.hasReportedPosition && $0.windowID != controls.icon }
        let managed = placed
            .filter { $0.frame.minX < icon.frame.minX }
            .sorted { $0.frame.minX < $1.frame.minX }

        var dividersSeen = 0
        entries = managed.map { item in
            guard controls.dividers.contains(item.windowID) else { return .item(item) }
            defer { dividersSeen += 1 }
            return .divider(dividersSeen == 0 ? .alwaysHidden : .hidden, item.windowID)
        }
        systemItems = placed
            .filter { $0.frame.minX > icon.frame.minX }
            .sorted { $0.frame.minX < $1.frame.minX }
        unplacedItems = items.filter { !$0.hasReportedPosition && !controls.dividers.contains($0.windowID) }
        let leftmostOnScreenX = (managed + [icon]).filter(\.isOnScreen).map(\.frame.minX).min() ?? icon.frame.minX
        notDrawnItems = Set(entries.compactMap(\.item).filter { item in
            !item.isOnScreen
                && statusArea.contains(item.frame.minX)
                && statusArea.contains(item.frame.maxX)
                && item.frame.minX > leftmostOnScreenX
        }.map(\.windowID))
    }

    /// Reads a layout without knowing Barbarian's control items' IDs, as a
    /// separate process must, and as Barbarian must for a menu bar that holds
    /// copies of its windows. Barbarian's three windows, owned by
    /// `barbarianPID`, are left to right the Always Hidden divider, the Hidden
    /// divider and the icon.
    public init?(items: [MenuBarItem], barbarianPID: Int32, statusArea: ClosedRange<CGFloat>) {
        let barbarianWindows = items
            .filter { $0.ownerPID == barbarianPID }
            .sorted { $0.frame.minX < $1.frame.minX }
            .map(\.windowID)
        guard barbarianWindows.count == 3 else { return nil }
        self.init(
            items: items,
            controls: ControlItemIDs(icon: barbarianWindows[2], hiddenDivider: barbarianWindows[1], alwaysHiddenDivider: barbarianWindows[0]),
            statusArea: statusArea
        )
    }

    /// The divider that currently plays each role.
    public func windowID(of divider: Divider) -> WindowID? {
        for case .divider(let role, let id) in entries where role == divider { return id }
        return nil
    }

    public func role(of dividerID: WindowID?) -> Divider? {
        for case .divider(let role, let id) in entries where id == dividerID { return role }
        return nil
    }

    public func section(of id: WindowID) -> MenuBarSection? {
        var section = MenuBarSection.alwaysHidden
        for entry in entries {
            switch entry {
            case .divider(.alwaysHidden, _): section = .hidden
            case .divider(.hidden, _): section = .shown
            case .item(let item) where item.windowID == id: return section
            case .item: continue
            }
        }
        return nil
    }

    public func items(in section: MenuBarSection) -> [MenuBarItem] {
        entries.compactMap { entry in
            guard case .item(let item) = entry, self.section(of: item.windowID) == section else { return nil }
            return item
        }
    }

    public func isNotDrawn(_ item: MenuBarItem) -> Bool {
        notDrawnItems.contains(item.windowID)
    }

    /// Whether `item` is off screen for lack of room. This holds only while
    /// every section is shown, as the Arrange window keeps them: otherwise a
    /// collapsed section's items are off screen too.
    public func doesNotFitWithEverySectionShown(_ item: MenuBarItem) -> Bool {
        !item.isOnScreen && !isNotDrawn(item)
    }

    /// The entries in `order` where it names them, else in their own order,
    /// with `moving` taken out and put back at `index`. The Arrange window
    /// shows this while a drag or a drop is under way.
    public func entries(inOrder order: [WindowID]?, moving: Entry? = nil, to index: Int = 0) -> [Entry] {
        let entriesByID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result = order?.compactMap { entriesByID[$0] } ?? entries
        if let moving {
            result.removeAll { $0.id == moving.id }
            result.insert(moving, at: min(max(index, 0), result.count))
        }
        return result
    }

    /// Whether the entries are in `order`. Items their app is not drawing
    /// report stale frames, so their place is not compared.
    public func hasOrder(_ order: [WindowID]) -> Bool {
        entries.map(\.id).filter { !notDrawnItems.contains($0) } == order.filter { !notDrawnItems.contains($0) }
    }

    /// Where to drop `item` so it lands immediately left of `neighbor`.
    /// Nil when it is already there or the drop names the item itself.
    public func destination(placing item: WindowID, before neighbor: WindowID) -> MoveDestination? {
        guard item != neighbor else { return nil }
        let ids = entries.map(\.id)
        if let index = ids.firstIndex(of: item), index + 1 < ids.count, ids[index + 1] == neighbor {
            return nil
        }
        return .leftOf(neighbor)
    }

    /// Where to drop `entry`, an item or a divider, so it lands at `index`
    /// among the other entries, counting from the left.
    ///
    /// The move aims at the entry that will sit on its right, or at
    /// Barbarian's icon past the last entry. Items their app is not drawing
    /// report stale frames, so the move aims past them at the next entry.
    public func destination(moving entry: WindowID, to index: Int) -> MoveDestination? {
        let others = entries.map(\.id).filter { $0 != entry }
        let rightNeighbor = others.dropFirst(min(index, others.count)).first { !notDrawnItems.contains($0) }
        if let rightNeighbor {
            return destination(placing: entry, before: rightNeighbor)
        }
        return entries.last?.id == entry ? nil : .leftOf(controls.icon)
    }
}

extension MenuBarItem {
    /// macOS reports an item that does not fit at the origin and off screen.
    /// The origin is the top left of the main display, so on a display above
    /// or left of it an item can sit at x = 0 with another y.
    var hasReportedPosition: Bool {
        isOnScreen || frame.origin != .zero
    }
}
