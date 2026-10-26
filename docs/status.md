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

## Built, not yet verified

These need Accessibility permission or a real pointer, which no check has had.

- Moving items and dividers by dropping in the layout window.
- Dragging in the layout window with a real pointer: the spring animations, the haptic tick and the grab pointer.
- Revealing Hidden by resting the pointer on the empty part of the bar.
- Rehiding on a click outside the menu bar.
- The hot keys Control-Option-Command-B and Control-Option-Command-M.
- Left-click, Option-click and right-click on the icon.
- Item images inside the running app, which needs Barbarian to have Screen Recording.
- Hover reveal on the Studio Display and the rest of the multi-display behavior inside the running app.
- The Settings window inside the running app, its first-launch opening, and recording a shortcut. Its drawing was checked with `--render-settings`.
- Launch at login, the icon's highlight while revealed, and the error popover.
- Everything on macOS 26.

## Known gaps

- "Not in the Menu Bar" also lists items whose app has switched them off, such as the input source menu. macOS reports them the same way as items that do not fit.
- With two displays whose menu bars have the same height, copies of items their app is not drawing show up as extra entries. See `MenuBarMembership`.
- A Control Center item that is not drawn, such as Focus with no Focus on, has no Accessibility element. Barbarian names it "Control Center".
- An Accessibility name can include the item's status, as Wi-Fi's does, so it changes while you watch.
