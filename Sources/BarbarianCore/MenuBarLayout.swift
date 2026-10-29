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
    /// left of Barbarian's icon. Items their app is not drawing are left out.
    public let entries: [Entry]

    public let controls: ControlItemIDs

    /// Items right of Barbarian's icon, left to right. They belong to macOS
    /// and are not managed.
    public let systemItems: [MenuBarItem]

    /// Managed items off screen because their app is not drawing them, as
    /// Now Playing is when nothing plays, rather than because they do not
    /// fit, left to right by their last frames.
    ///
    /// macOS drops items that do not fit from the left end of the bar, so
    /// they sit left of every drawn item. An item its app is not drawing keeps
    /// its last frame, inside the visible bar and right of a drawn item.
    ///
    /// Such an item cannot be moved, and its frame says nothing about where
    /// it will appear. macOS saves its place as a distance from the screen's
    /// right edge, and a move posted while it is not drawn changes its frame
    /// without changing that distance.
    public let notDrawnItems: [MenuBarItem]

    /// Reads a layout from one menu bar's items. `statusArea` is the x range
    /// where status items can appear in that menu bar.
    ///
    /// Divider roles follow position, not identity: the left divider always
    /// separates Always Hidden from Hidden. That keeps the sections in order
    /// when someone drags one divider past the other.
    public init?(items: [MenuBarItem], controls: ControlItemIDs, statusArea: ClosedRange<CGFloat>) {
        guard let icon = items.first(where: { $0.windowID == controls.icon }) else { return nil }
        self.controls = controls

        let placed = items.filter { !$0.isSwitchedOff && $0.windowID != controls.icon }
        let managed = placed
            .filter { $0.frame.minX < icon.frame.minX }
            .sorted { $0.frame.minX < $1.frame.minX }

        let leftmostOnScreenX = (managed + [icon]).filter(\.isOnScreen).map(\.frame.minX).min() ?? icon.frame.minX
        let notDrawn = managed.filter { item in
            !item.isOnScreen
                && !controls.dividers.contains(item.windowID)
                && statusArea.contains(item.frame.minX)
                && statusArea.contains(item.frame.maxX)
                && item.frame.minX > leftmostOnScreenX
        }
        notDrawnItems = notDrawn
        entries = Self.assigningDividerRoles(managed.filter { !notDrawn.contains($0) }.map { item in
            controls.dividers.contains(item.windowID) ? .divider(.hidden, item.windowID) : .item(item)
        })
        systemItems = placed
            .filter { $0.frame.minX > icon.frame.minX }
            .sorted { $0.frame.minX < $1.frame.minX }
    }

    private init(entries: [Entry], controls: ControlItemIDs, systemItems: [MenuBarItem], notDrawnItems: [MenuBarItem]) {
        self.entries = entries
        self.controls = controls
        self.systemItems = systemItems
        self.notDrawnItems = notDrawnItems
    }

    /// This layout, read after revealing every section, with the items their
    /// app is not drawing set aside, compared with `baseline`, a layout read
    /// in `baselineState` before revealing.
    ///
    /// Revealing a collapsed section moves every drawn item in it. An item
    /// of a collapsed section that is off screen with the same frame as in
    /// `baseline` is not drawn. Items of sections that were already shown do
    /// not move, so their frames tell nothing.
    public func settingAsideStaleItems(comparedWith baseline: MenuBarLayout, revealedFrom baselineState: HidingState) -> MenuBarLayout {
        let baselineFrames = Dictionary(baseline.entries.compactMap(\.item).map { ($0.windowID, $0.frame) }, uniquingKeysWith: { first, _ in first })
        func wasCollapsed(_ id: WindowID) -> Bool {
            switch baseline.section(of: id) {
            case .alwaysHidden: baselineState.isCollapsed(.alwaysHidden)
            case .hidden: baselineState.isCollapsed(.hidden)
            case .shown, nil: false
            }
        }
        let stale = entries.compactMap(\.item).filter { item in
            !item.isOnScreen && wasCollapsed(item.windowID) && baselineFrames[item.windowID] == item.frame
        }
        guard !stale.isEmpty else { return self }
        return MenuBarLayout(
            entries: Self.assigningDividerRoles(entries.filter { entry in !stale.contains { $0.windowID == entry.id } }),
            controls: controls,
            systemItems: systemItems,
            notDrawnItems: (notDrawnItems + stale).sorted { $0.frame.minX < $1.frame.minX }
        )
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

    /// The positions in `order`, a rearranged copy of `entries`, of the
    /// items that would not fit with every section shown, as the Arrange
    /// panel keeps them.
    ///
    /// macOS fills the bar from the right and leaves out the leftmost items
    /// once it is full. As many items fit as are on screen now, so the items
    /// left of that many, counted from the right, do not fit.
    public func positionsThatDoNotFitWithEverySectionShown(inOrder order: [Entry]) -> [Int] {
        let fitCount = entries.compactMap(\.item).filter(\.isOnScreen).count
        let itemPositions = order.indices.filter { order[$0].item != nil }
        return Array(itemPositions.dropLast(fitCount))
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

    public func hasOrder(_ order: [WindowID]) -> Bool {
        entries.map(\.id) == order
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
    /// Barbarian's icon past the last entry.
    public func destination(moving entry: WindowID, to index: Int) -> MoveDestination? {
        let others = entries.map(\.id).filter { $0 != entry }
        guard index < others.count else { return entries.last?.id == entry ? nil : .leftOf(controls.icon) }
        return destination(placing: entry, before: others[index])
    }
}

extension MenuBarItem {
    /// macOS reports an item its app has switched off, as the input menu is
    /// when hidden, at the origin and off screen. An item that does not fit
    /// keeps a real position, often left of the screen.
    /// The origin is the top left of the main display, so on a display above
    /// or left of it an item can sit at x = 0 with another y.
    var isSwitchedOff: Bool {
        !isOnScreen && frame.origin == .zero
    }
}
