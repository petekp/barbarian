# Architecture

Barbarian is a Swift package with three targets. The app is a menu bar agent with no Dock icon (`LSUIElement`).

| Target | Holds | Depends on |
|---|---|---|
| `BarbarianCore` | Models and decisions as plain values: `MenuBarItem`, `MenuBarMembership`, `MenuBarLayout`, `ArrangeStrip`, `ItemNaming`, `SystemItem`, `HidingState`, `AutoRehidePolicy`, `MoveDestination` | Core Graphics geometry only |
| `BarbarianSystem` | macOS adapters: `MenuBarDisplay`, `MenuBar`, `MenuBarWindowList`, `MenuBarItemImages`, `ScreenRecordingPermission`, `AppMenus`, `MenuBarItemEvents`, `AccessibilityPermission`, `AccessibilityItemLabels`, `GlobalHotKey` | Core |
| `BarbarianApp` | `AppController`, `ControlItems`, `ItemsMenu`, `ItemAccess`, `ItemImageCache`, the Arrange panel, `CommandChannel` | Core and System |

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

**Reading the bar.** `MenuBarWindowList.allWindows()` reads every window at the status window level from `CGWindowListCopyWindowInfo`. A `MenuBar` is one display's menu bar and its items, from one such read; `MenuBarMembership` decides which windows belong to it. The active menu bar is the one holding Barbarian's icon window. The command-line tools find that window by its title, through `RunningBarbarian`. `MenuBarDisplay` describes each display's menu bar: its bounds, its height and where status items can appear. `MenuBarLayout` sorts the managed items by x, assigns sections, and notes which items their app is not drawing. It needs no permission.

**Revealing and rehiding.** Clicking the icon toggles Hidden. Option-click toggles everything. A shortcut, Control-Option-Command-B unless changed in Settings, toggles Hidden from anywhere. The icon is highlighted while a section is revealed. Barbarian acts on the press and consumes it, as macOS's own items do, because AppKit's own press-and-release highlight fights that highlight and makes the icon flicker. One quarter-second timer in `AppController` does two jobs. It reveals Hidden when the pointer rests on the empty stretch of any display's menu bar: the visible part of the collapsed right divider, right of the notch or of the app's menus. On a display without a notch, `AppMenus` reads where the app's menus end through Accessibility, and without the permission hover does nothing there. It hides revealed items once the pointer has been out of the menu bar for the delay set in Settings, unless a menu is open or the Arrange panel is open. A click outside the menu bar also rehides.

**Item images.** When "Show items' own icons" is on in Settings (`Preferences.showsItemImages`, off by default) and Barbarian has Screen Recording, `MenuBarItemImages` captures items' own images through ScreenCaptureKit, and `ItemImageCache` keeps them, trimmed to the drawn pixels. A one-color image becomes a template image so it follows light and dark mode. Each capture request can raise macOS's screen recording alert, so a round is one request: the stretch of menu bar holding the items, with every other window excluded, cut into each item's image. A display capture that includes only the items' windows comes back blank. A new round waits until macOS answers the previous request. Only on-screen items can be captured, so items are captured when a section is revealed and when the items menu or the Arrange panel opens, and a hidden item keeps its last image. Without a capture, `ItemPresentation` draws one of macOS's own items, such as Wi-Fi or Focus, with an SF Symbol that looks like it, and names it (`SystemItem`, found by Accessibility identifier, window title or owning app), and any other item with its app's icon.

**Names.** `ItemNaming` in Core picks an item's name: the app's name, unless the app owns several items or is part of macOS, such as SystemUIServer for Siri. Then it uses a known Control Center title, the Accessibility name, or the window title. `ItemPresentation` gathers those inputs once per layout.

**The items menu.** Right-click or Control-click the icon, or press its shortcut, Control-Option-Command-M unless changed. `ItemsMenu` lists managed items by section, then unplaced items. It leaves out items whose app is not drawing them. Typing selects an item by name.

**Opening an item.** `ItemAccess` handles a pick from the menu. With Accessibility, an on-screen item is clicked. An off-screen item is moved left of the icon, clicked, and moved back once its menu closes. Without Accessibility, Barbarian reveals the item's section, and asks for the permission if the item still does not fit.

**Moving items.** `MenuBarItemEvents.move` posts a Command-mouse-down addressed to the item's window, then a mouse-up addressed to the target item's window at the target's edge. That is the system's own Command-drag gesture. The window fields deliver the events even when the item is off screen. It retries up to three times, checking whether the item's frame changed. The pointer is hidden during the move and put back afterwards.

**The Arrange panel.** Arrange Menu Bar is a borderless panel (`LayoutPanel`) pinned to the top right of the display holding Barbarian's icon, just below the menu bar. While it is open, every display is dimmed below the menu bar, and a click on the dimmed area, Escape or the close button closes it. It shows the managed part of the menu bar as one strip, left to right: Always Hidden, the left divider, Hidden, the right divider, Shown, then Barbarian's icon and macOS's own items for context. `ArrangeStrip` in Core computes every entry's frame and each section's span. The panel draws entries at those frames and hit-tests the dragged entry's center against a strip without it, never against the frames entries are animating through, so an entry sliding under the pointer cannot change the drop target. All entries sit in one SwiftUI view keyed by window ID, so a dropped entry slides into place as one move. The panel keeps every section shown. When the bar is full macOS leaves out the leftmost items, and as many items fit as are on screen, so `MenuBarLayout.positionsThatDoNotFitWithEverySectionShown` marks the items left of that many, counted from the right, in whatever order the panel shows. That keeps the cutoff right during a drag. The panel shades those items and draws a dashed line where the room ends, with one label under it: "Cut off by the notch" on a display with a notch, otherwise a count. The room depends on the front app's menus, and while the panel is open Barbarian is the front app.

Opening reads the layout before revealing every section, then waits until two reads 100 ms apart agree before showing the panel, so it never shows the menu bar mid-reveal. Revealing moves every drawn item, so an item off screen whose frame has not changed since that first read is one its app is not drawing: `MenuBarLayout.keepingStaleItems(asIn:)` puts it back beside the entry it followed in the first read, instead of placing it by its stale frame against the dividers' new positions.

Animation is explicit. Views carry no `.animation(_:value:)` for position; `LayoutEditorModel` wraps the three changes that should move entries in `withAnimation`: the drop target changing, the drop, and a new layout read after the panel has opened. The dragged entry opts out through a transaction, so it follows the pointer exactly. While a dropped order is pending, refreshes show nothing until the menu bar reports that order or 2 seconds pass. From the start of a drag until its move settles, the canvas width is frozen, because the panel is pinned by its right edge and a resize would shift the strip under the pointer. The canvas always reserves room for the cutoff label, so its height never changes.

Items and both dividers can be dragged. Dragging a divider moves Barbarian's own status item, which changes which items are in which section. On drop, `MenuBarLayout.destination(moving:to:)` picks the move. It aims past items their app is not drawing, whose frames are stale. The panel keeps showing the dropped order until the menu bar reports it, for up to 2 seconds, so the entry does not jump back while the move runs. Items their app is not drawing show a dotted outline and "Not showing", and cannot be dragged. Items with no place in the menu bar are left out; the items menu still lists them. While the panel is open every section is revealed and stays revealed.

**Commands.** `Barbarian --command <name>` posts a distributed notification that the running app handles. Scripts and agents use it to drive the app without clicking. Any process can post a distributed notification, and the app holds Accessibility permission, so the commands, like the other development flags, exist only in debug builds.

**Updates.** Release builds check for updates with Sparkle (`SPUStandardUpdaterController` in `AppController`). The feed, `SUFeedURL` in `Info.plist`, is the `appcast.xml` attached to the latest GitHub release. Sparkle installs only updates signed with the private half of `SUPublicEDKey`, which lives in the release maker's keychain under the account `barbarian`. Debug builds never start the updater, so a release cannot replace a development build. Barbarian is not sandboxed, so `scripts/build-app.sh` leaves out Sparkle's XPC services.

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
