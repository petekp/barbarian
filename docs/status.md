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
- Item names read through Accessibility, checked with `--print-items` from a terminal that has Accessibility, on 2026-10-26. Control Center's drawn items get their own names, such as "Wi‑Fi, connected, 3 bars".

## Built, not yet verified

These need Accessibility permission or a real pointer, which no check has had.

- Moving items: dropping in the layout window, and the move-click-return sequence when opening an off-screen item from the menu.
- Clicking items with posted events.
- Revealing Hidden by resting the pointer on the empty part of the bar.
- Rehiding on a click outside the menu bar.
- The hot keys Control-Option-Command-B and Control-Option-Command-M.
- Left-click, Option-click and right-click on the icon.
- Everything on macOS 26.

## Known gaps

- "Not in the Menu Bar" also lists items whose app has switched them off, such as the input source menu. macOS reports them the same way as items that do not fit.
- The layout window still shows items whose app is not drawing them, dimmed.
- Only the main display's menu bar is managed.
- A Control Center item that is not drawn, such as Focus with no Focus on, has no Accessibility element. Barbarian names it "Control Center".
- An Accessibility name can include the item's status, as Wi-Fi's does, so it changes while you watch.
