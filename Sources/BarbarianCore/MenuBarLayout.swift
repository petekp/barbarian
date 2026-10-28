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

        entries = Self.assigningDividerRoles(managed.map { item in
            controls.dividers.contains(item.windowID) ? .divider(.hidden, item.windowID) : .item(item)
        })
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

    private init(entries: [Entry], unplacedItems: [MenuBarItem], controls: ControlItemIDs, systemItems: [MenuBarItem], notDrawnItems: Set<WindowID>) {
        self.entries = entries
        self.unplacedItems = unplacedItems
        self.controls = controls
        self.systemItems = systemItems
        self.notDrawnItems = notDrawnItems
    }

    /// This layout, read after revealing every section, with the items their
    /// app is not drawing put back where they were in `baseline`, a layout
    /// read in `baselineState` before revealing.
    ///
    /// Revealing a collapsed section moves every drawn item in it. An item
    /// of a collapsed section that is off screen with the same frame as in
    /// `baseline` is not drawn: its frame is stale and would place it by
    /// where the dividers are now. It goes back right of the entry it
    /// followed in `baseline`, so its section holds still. Items of sections
    /// that were already shown do not move, so their frames tell nothing.
    public func keepingStaleItems(asIn baseline: MenuBarLayout, revealedFrom baselineState: HidingState) -> MenuBarLayout {
        let baselineFrames = Dictionary(baseline.entries.compactMap(\.item).map { ($0.windowID, $0.frame) }, uniquingKeysWith: { first, _ in first })
        func wasCollapsed(_ id: WindowID) -> Bool {
            switch baseline.section(of: id) {
            case .alwaysHidden: baselineState.isCollapsed(.alwaysHidden)
            case .hidden: baselineState.isCollapsed(.hidden)
            case .shown, nil: false
            }
        }
        let stale = Set(entries.compactMap(\.item).filter { item in
            guard !item.isOnScreen else { return false }
            return isNotDrawn(item)
                || (wasCollapsed(item.windowID) && baselineFrames[item.windowID] == item.frame)
        }.map(\.windowID))
        guard !stale.isEmpty else { return self }

        var ordered = entries.filter { !stale.contains($0.id) }
        let baselineIDs = baseline.entries.map(\.id)
        for staleEntry in entries where stale.contains(staleEntry.id) {
            let leftNeighbor = baselineIDs.firstIndex(of: staleEntry.id).flatMap { index in
                baselineIDs[..<index].last { id in ordered.contains { $0.id == id } }
            }
            let insertionIndex = leftNeighbor.flatMap { id in ordered.firstIndex { $0.id == id } }.map { $0 + 1 } ?? 0
            ordered.insert(staleEntry, at: insertionIndex)
        }
        return MenuBarLayout(entries: Self.assigningDividerRoles(ordered), unplacedItems: unplacedItems, controls: controls, systemItems: systemItems, notDrawnItems: stale)
    }

    /// The entries with each divider's role set by position: the left
    /// divider plays Always Hidden, the other Hidden.
    private static func assigningDividerRoles(_ entries: [Entry]) -> [Entry] {
        var dividersSeen = 0
        return entries.map { entry in
            guard case .divider(_, let id) = entry else { return entry }
            defer { dividersSeen += 1 }
            return .divider(dividersSeen == 0 ? .alwaysHidden : .hidden, id)
        }
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

    /// The positions in `order`, a rearranged copy of `entries`, of the
    /// items that would not fit with every section shown, as the Arrange
    /// panel keeps them.
    ///
    /// macOS fills the bar from the right and leaves out the leftmost items
    /// once it is full. As many items fit as are on screen now, so the items
    /// left of that many, counted from the right, do not fit. Items their
    /// app is not drawing take no room.
    public func positionsThatDoNotFitWithEverySectionShown(inOrder order: [Entry]) -> [Int] {
        let fitCount = entries.compactMap(\.item).filter { $0.isOnScreen && !isNotDrawn($0) }.count
        let drawnPositions = order.indices.filter { order[$0].item.map { !isNotDrawn($0) } ?? false }
        return Array(drawnPositions.dropLast(fitCount))
    }

    /// The entries in `order` where it names them, else in their own order,
    /// with `moving` taken out and put back at `index`. The Arrange panel
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
