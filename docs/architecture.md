# Architecture

Barbarian is a Swift package with three targets. The app is a menu bar agent with no Dock icon (`LSUIElement`).

| Target | Holds | Depends on |
|---|---|---|
| `BarbarianCore` | Models and decisions as plain values: `MenuBarItem`, `MenuBarMembership`, `MenuBarLayout`, `ArrangeStrip`, `HidingState`, `AutoRehidePolicy`, `MoveDestination` | Core Graphics geometry only |
| `BarbarianSystem` | macOS adapters: `MenuBarDisplay`, `MenuBarWindowList`, `MenuBarItemImages`, `ScreenRecordingPermission`, `AppMenus`, `MenuBarItemEvents`, `AccessibilityPermission`, `AccessibilityItemNames`, `GlobalHotKey` | Core |
| `BarbarianApp` | `AppController`, `ControlItems`, `ItemsMenu`, `ItemAccess`, `ItemImageCache`, the layout window, `CommandChannel` | Core and System |

`swift test` covers Core. System and App are checked by running the app; see `AGENTS.md`.

## Terms

- **Item**: a status item window in the menu bar, owned by some app. `MenuBarItem` is one item as the window server reports it.
- **Control items**: Barbarian's own three items. The icon sits rightmost of the items Barbarian manages. Two dividers sit to its left.
- **Section**: Shown, Hidden or Always Hidden. Items left of the left divider are Always Hidden. Items between the dividers are Hidden. Items between the right divider and the icon are Shown. Items right of the icon belong to macOS (Control Center, Siri, the clock) and are not managed.
- **Collapsed divider**: a divider stretched to 10,000 points. macOS lays out everything to its left off screen.
- **Active menu bar**: the menu bar of the display in use. Barbarian finds it as the menu bar holding its own icon's window. With several displays, each has a menu bar and each item has a window in every one. The item's own window sits in the active menu bar and the rest are copies. Barbarian reads, moves and clicks items in the active menu bar.
- **Unplaced item**: an item macOS gives no position, because it does not fit or its app has hidden it.

## How each feature works

**Hiding.** `HidingState` says which dividers are collapsed. `ControlItems.apply` sets each divider's length. Divider roles follow position: whichever divider is further left plays Always Hidden, so the sections stay in order if someone drags one divider past the other.

**Reading the bar.** `MenuBarWindowList.items()` reads every window at the status window level from `CGWindowListCopyWindowInfo`, and `MenuBarMembership` keeps the ones that belong to the active menu bar. `MenuBarDisplay` describes each display's menu bar: its bounds, its height and where status items can appear. `MenuBarLayout` sorts the managed items by x and assigns sections. It needs no permission.

**Revealing and rehiding.** Clicking the icon toggles Hidden. Option-click toggles everything. A shortcut, Control-Option-Command-B unless changed in Settings, toggles Hidden from anywhere. The icon is highlighted while a section is revealed. One quarter-second timer in `AppController` does two jobs. It reveals Hidden when the pointer rests on the empty stretch of any display's menu bar: the visible part of the collapsed right divider, right of the notch or of the app's menus. On a display without a notch, `AppMenus` reads where the app's menus end through Accessibility, and without the permission hover does nothing there. It hides revealed items once the pointer has been out of the menu bar for the delay set in Settings, unless a menu is open or the layout window is open. A click outside the menu bar also rehides.

**Item images.** With Screen Recording, `MenuBarItemImages` captures items' own images through ScreenCaptureKit, and `ItemImageCache` keeps them, trimmed to the drawn pixels. A one-color image becomes a template image so it follows light and dark mode. Only on-screen items can be captured, so the cache refreshes on-screen items every 10 seconds and right after a section is revealed, and keeps a hidden item's last image. `ItemPresentation` falls back to the app's icon.

**The items menu.** Right-click or Control-click the icon, or press its shortcut, Control-Option-Command-M unless changed. `ItemsMenu` lists managed items by section, then unplaced items. It leaves out items whose app is not drawing them, using `MenuBarLayout.isHiddenByItsApp`. Typing selects an item by name.

**Opening an item.** `ItemAccess` handles a pick from the menu. With Accessibility, an on-screen item is clicked. An off-screen item is moved left of the icon, clicked, and moved back once its menu closes. Without Accessibility, Barbarian reveals the item's section, and asks for the permission if the item still does not fit.

**Moving items.** `MenuBarItemEvents.move` posts a Command-mouse-down addressed to the item's window, then a mouse-up addressed to the target item's window at the target's edge. That is the system's own Command-drag gesture. The window fields deliver the events even when the item is off screen. It retries up to three times, checking whether the item's frame changed. The pointer is hidden during the move and put back afterwards.

**The layout window.** Arrange Menu Bar shows the managed part of the menu bar as one strip, left to right: Always Hidden, the left divider, Hidden, the right divider, Shown, then Barbarian's icon and macOS's own items for context. `ArrangeStrip` in Core computes every entry's frame and each section's span. The window draws entries at those frames and hit-tests the dragged entry's center against a strip without it, never against the frames entries are animating through, so an entry sliding under the pointer cannot change the drop target. All entries sit in one SwiftUI view keyed by window ID, so a dropped entry slides into place as one move.

Items and both dividers can be dragged. Dragging a divider moves Barbarian's own status item, which changes which items are in which section. On drop, `MenuBarLayout.destination(moving:to:unreliableNeighbors:)` picks the move. It aims past items their app is not drawing, whose frames are stale. The window keeps showing the dropped order until the menu bar reports it, for up to 2 seconds, so the entry does not jump back while the move runs. Items their app is not drawing are drawn small with a dotted outline and cannot be dragged. Items that don't fit are dimmed and say so. Items with no place in the menu bar are left out; the items menu still lists them. While the window is open every section is revealed and stays revealed.

**Commands.** `Barbarian --command <name>` posts a distributed notification that the running app handles. Scripts and agents use it to drive the app without clicking.

## macOS behavior the code relies on

Observed on macOS 15.7 on a 14-inch MacBook Pro with a notch, unless noted.

- On a display with a notch, status items appear only right of the notch. `NSScreen.auxiliaryTopRightArea` gives that area. Items that do not fit are dropped from the left end.
- An item that does not fit is reported off screen at x = 0.
- Items left of a collapsed divider are reported off screen at a large negative x, in their real order. This is why sections can be read while collapsed.
- An item whose app stops drawing it, such as Now Playing with nothing playing, is reported off screen at a frame inside the visible bar.
- A status item with no saved position appears at the left end of the status items. Barbarian relies on this so that the dividers start left of everything on first launch and nothing is hidden.
- macOS saves each item's position in its app's preferences under `NSStatusItem Preferred Position <autosave name>`. Higher values sit further left. Barbarian seeds 0 for its icon so it starts rightmost.
- With several displays, an item's own window sits in the active menu bar and keeps its window ID when another display becomes active: it moves there within about a second, and the copies move the other way. Observed on 2026-10-26 with a Studio Display above the MacBook Pro.
- A window keeps the height of the menu bar it belongs to: 37 points on the built-in display with a notch, 24 on the Studio Display. Copies of items whose app is not drawing them stay parked in the other menu bar with their own bar's height, so height tells them apart.
- Window titles of other apps' windows are withheld from processes without Screen Recording permission. Accessibility reports item names instead.
- Posted mouse events from a process without Accessibility permission are dropped.
- A ScreenCaptureKit capture of an off-screen status item window never completes. `MenuBarItemImages` skips off-screen items and drops a capture after a second. `CGWindowListCreateImage`, the older capture call, is unavailable from the macOS 15 SDK on.

## Risks

- `MenuBarItemEvents` uses an undocumented event field, `0x33`, as Ice does. A macOS update could change its meaning.
- Moving and clicking have not been verified yet. See `docs/status.md`.
- Nothing here has been checked on macOS 26. In particular, it is unverified whether status item windows are still owned by their apps there.
- When two displays' menu bars have the same height, copies of items their app is not drawing cannot be told apart from real items. They appear as extra, nameless entries.
