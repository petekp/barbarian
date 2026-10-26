# Architecture

Barbarian is a Swift package with three targets. The app is a menu bar agent with no Dock icon (`LSUIElement`).

| Target | Holds | Depends on |
|---|---|---|
| `BarbarianCore` | Models and decisions as plain values: `MenuBarItem`, `MenuBarMembership`, `MenuBarLayout`, `HidingState`, `AutoRehidePolicy`, `MoveDestination` | Core Graphics geometry only |
| `BarbarianSystem` | macOS adapters: `MenuBarDisplay`, `MenuBarWindowList`, `AppMenus`, `MenuBarItemEvents`, `AccessibilityPermission`, `AccessibilityItemNames`, `GlobalHotKey` | Core |
| `BarbarianApp` | `AppController`, `ControlItems`, `ItemsMenu`, `ItemAccess`, the layout window, `CommandChannel` | Core and System |

`swift test` covers Core. System and App are checked by running the app; see `AGENTS.md`.

## Terms

- **Item**: a status item window in the menu bar, owned by some app. `MenuBarItem` is one item as the window server reports it.
- **Control items**: Barbarian's own three items. The icon sits rightmost of the items Barbarian manages. Two dividers sit to its left.
- **Section**: Shown, Hidden or Always Hidden. Items left of the left divider are Always Hidden. Items between the dividers are Hidden. Items between the right divider and the icon are Shown. Items right of the icon belong to macOS (Control Center, Siri, the clock) and are not managed.
- **Collapsed divider**: a divider stretched to 10,000 points. macOS lays out everything to its left off screen.
- **Active menu bar**: the menu bar of the display with keyboard focus. With several displays, each has a menu bar and each item has a window in every one. The item's own window sits in the active menu bar and the rest are copies. Barbarian reads, moves and clicks items in the active menu bar.
- **Unplaced item**: an item macOS gives no position, because it does not fit or its app has hidden it.

## How each feature works

**Hiding.** `HidingState` says which dividers are collapsed. `ControlItems.apply` sets each divider's length. Divider roles follow position: whichever divider is further left plays Always Hidden, so the sections stay in order if someone drags one divider past the other.

**Reading the bar.** `MenuBarWindowList.items()` reads every window at the status window level from `CGWindowListCopyWindowInfo`, and `MenuBarMembership` keeps the ones that belong to the active menu bar. `MenuBarDisplay` describes each display's menu bar: its bounds, its height and where status items can appear. `MenuBarLayout` sorts the managed items by x and assigns sections. It needs no permission.

**Revealing and rehiding.** Clicking the icon toggles Hidden. Option-click toggles everything. Control-Option-Command-B toggles Hidden from anywhere. One quarter-second timer in `AppController` does two jobs. It reveals Hidden when the pointer rests on the empty stretch of any display's menu bar: the visible part of the collapsed right divider, right of the notch or of the app's menus. On a display without a notch, `AppMenus` reads where the app's menus end through Accessibility, and without the permission hover does nothing there. It hides revealed items once the pointer has been out of the menu bar for `AutoRehidePolicy.delay`, unless a menu is open or the layout window is open. A click outside the menu bar also rehides.

**The items menu.** Right-click or Control-click the icon, or press Control-Option-Command-M. `ItemsMenu` lists managed items by section, then unplaced items. It leaves out items whose app is not drawing them, using `MenuBarLayout.isHiddenByItsApp`. Typing selects an item by name.

**Opening an item.** `ItemAccess` handles a pick from the menu. With Accessibility, an on-screen item is clicked. An off-screen item is moved left of the icon, clicked, and moved back once its menu closes. Without Accessibility, Barbarian reveals the item's section, and asks for the permission if the item still does not fit.

**Moving items.** `MenuBarItemEvents.move` posts a Command-mouse-down addressed to the item's window, then a mouse-up addressed to the target item's window at the target's edge. That is the system's own Command-drag gesture. The window fields deliver the events even when the item is off screen. It retries up to three times, checking whether the item's frame changed. The pointer is hidden during the move and put back afterwards.

**The layout window.** Arrange Menu Bar shows each section's items in menu bar order, wrapping left to right. `ArrangeGrid` in Core computes every section's and slot's frame. The window draws items at those frames and hit-tests the pointer against them, never against the frames items are animating through, so an item sliding under the pointer cannot change the drop target. All items sit in one SwiftUI view keyed by window ID, so an item dragged into another section slides there as one move.

While you drag, the item follows the pointer and the others spring aside to open a gap at the drop target. On drop, `MenuBarLayout.destination(inserting:into:at:unreliableNeighbors:)` picks the move. It aims past items their app is not drawing, whose frames are stale. The window keeps showing the dropped order until the menu bar reports it, for up to 2 seconds, so the item does not jump back while the move runs. Items not in the menu bar cannot be dragged. Each dimmed item says why: "Not showing" when its app is not drawing it, "Doesn't fit" otherwise. While the window is open every section is revealed and stays revealed.

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

## Risks

- `MenuBarItemEvents` uses an undocumented event field, `0x33`, as Ice does. A macOS update could change its meaning.
- Moving and clicking have not been verified yet. See `docs/status.md`.
- Nothing here has been checked on macOS 26. In particular, it is unverified whether status item windows are still owned by their apps there.
- When two displays' menu bars have the same height, copies of items their app is not drawing cannot be told apart from real items. They appear as extra, nameless entries.
