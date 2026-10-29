# Status

What has been checked on a real Mac, and what has not. Update this file when a check runs or a feature changes.

## Verified

Checked on macOS 15.7 on a 14-inch MacBook Pro with a notch, without Accessibility permission, on 2026-10-25. Positions were read with `--print-items` and the bar was captured with `screencapture`.

- First launch puts the icon rightmost and both dividers at the far left, so nothing is hidden.
- A collapsed divider moves every item on its left off screen. Sections still read correctly while collapsed.
- `show-hidden` reveals Hidden. `show-all` reveals both sections. Revealed items hide again about 4 seconds after the pointer leaves the menu bar.
- The items menu lists items by section with app icons. It leaves out items whose app is not drawing them.
- The layout window opens in front and shows one row per section in menu bar order.
- `scripts/build-app.sh` signs with the same Apple Development certificate on every build.
- The Arrange window's strip, rendered with `--render-arrange` on 2026-10-26: sections in menu bar order with both dividers, and a lifted item opens a gap at its target.
- Opening an off-screen item, with Accessibility, on 2026-10-26: `--command open-item 515` moved OrbStack from Always Hidden to the left of the icon, clicked it so its menu opened, and moved it back once the menu closed. Every item ended in its original order and section.
- Item names read through Accessibility, checked with `--print-items` from a terminal that has Accessibility, on 2026-10-26. Control Center's drawn items get their own names, such as "Wi‑Fi, connected, 3 bars".

- Item images, rendered with `--render-arrange` from a terminal with Screen Recording on 2026-10-26: on-screen items show their own image, and hidden items show their app's icon until they have been on screen.
- Reading the active menu bar with two displays, checked with `--print-items` on 2026-10-26 with the built-in display active: one entry per item, with real window IDs and Accessibility names.

Checked in a Tart VM on macOS 15.7.7 with Accessibility, on 2026-10-28, with a debug build and eight placeholder menu bar apps spread across the sections. Clicks and drags went through the VM's VNC. Modifier keys, Option-click and hot keys were posted as CGEvents from the guest.

- First launch on a new account: the icon is rightmost, both dividers sit at the far left, Settings opens by itself, and launch at login turns on with a "Login Item Added" notice. Turning it off in Settings removes the login item.
- A click on the icon reveals Hidden and highlights the icon. Option-click reveals everything. Resting the pointer on the empty part of the bar reveals Hidden within a second.
- Revealed items hide again about 4 seconds after the pointer leaves the bar, stay while the pointer is in it, and hide at once on a click elsewhere.
- Right-click and Control-Option-Command-M open the items menu by section. Picking an off-screen item moves it beside the icon, opens its menu, and moves it back once the menu closes. Typing an item's name and pressing Return opens it too.
- Control-Option-Command-B toggles Hidden.
- The Arrange panel opens at the top right with the rest of the screen dimmed. Dragging an item to another section and back, and dragging a divider, moved the real items, checked with `--print-items`. Escape, the close button and a click on the dimmed area each close it.
- Check for Updates… is in the items menu and disabled in a debug build.

Checked in the same VM on 2026-10-29 with Now Playing, which macOS draws only while something plays. The same posted Command-drag Barbarian uses moved Now Playing while it was drawn, and macOS saved the new position. Posted while it was not drawn, the drag changed the frame the window list reports, but macOS kept the saved position, and Now Playing came back in its old place when playback resumed. So an item that is not drawn cannot be moved, and its frame changing does not show a move landed. The Arrange panel shows such items in their own row, apart from the strip.

## Built, not yet verified

- The Arrange panel's motion: opening without items sliding, the frozen width during a drag, the haptic tick and the hold after a drop until the menu bar matches.
- The Clock's icon and the "Cut off by the notch" label in the running app. Checked only with `--render-arrange`.
- Item images inside the running app, which needs Barbarian to have Screen Recording.
- Hover reveal on the Studio Display and the rest of the multi-display behavior inside the running app.
- Recording a shortcut in Settings, and the error popover.
- A notarized release build: Gatekeeper, the hardened runtime with Accessibility, and Sparkle's update check, Check for Updates… and installing an update. They need a published release.
- Everything on macOS 26.

## Known gaps

- With two displays whose menu bars have the same height, copies of items their app is not drawing show up as extra entries. See `MenuBarMembership`.
- A Control Center item that is not drawn, such as Focus with no Focus on, has no Accessibility element. Barbarian names it "Control Center".
- An Accessibility name can include the item's status, as Wi-Fi's does, so it changes while you watch.
- An item in Shown that does not fit keeps the same frame when sections are revealed, so it is told apart only by the cutoff count, not by its frame.
