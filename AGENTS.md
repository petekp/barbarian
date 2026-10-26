# Barbarian

Barbarian is Pete's personal macOS menu bar manager. It hides menu bar items, lists every item so hidden ones stay reachable, and rearranges items. It targets macOS 15 and 26.

Agents build and maintain all of it. Read these before changing behavior:

- `docs/architecture.md`: the modules, how each feature works, and the macOS behavior the code depends on.
- `docs/status.md`: what has been verified on a real Mac and what has not.
- `docs/feature-scope.md`: what is in and out of scope, with reasons. Check it before adding a feature.

## Commands

| Task | Command |
|---|---|
| Unit tests | `swift test` |
| Build, sign and install to `~/Applications/Barbarian.app` | `scripts/build-app.sh` |
| Quit the running copy and open the installed one | `scripts/restart-app.sh` |
| Redraw `Resources/AppIcon.icns` after changing the axe or the icon colors | `scripts/make-app-icon.sh` |
| List the active menu bar's items with title, Accessibility name, position and section | `.build/debug/Barbarian --print-items` |
| Render the Arrange window to a PNG without opening it, optionally with an item or divider mid-drag | `.build/debug/Barbarian --render-arrange <file.png> [--lift <window ID> <index>] [--item-images]` |
| Render the Settings window to a PNG without opening it | `.build/debug/Barbarian --render-settings <file.png>` |
| Drive the running app | `.build/debug/Barbarian --command <name>` |

`--command` takes `show-hidden`, `show-all`, `hide`, `open-menu`, `open-layout`, `close-layout` and `open-item <window ID>`. `open-item` opens an item as picking it from the menu does, so it moves and clicks other apps' items. Send build and test output to a log under `.build/logs/` and check the exit status.

## Where code goes

- `BarbarianCore` holds logic that needs no AppKit: reading sections from item positions, drop destinations, the rehide rule. Put new logic here and cover it with Swift Testing tests in `Tests/BarbarianCoreTests`.
- `BarbarianSystem` wraps macOS APIs: the window list, Accessibility, posted mouse events, hot keys. Keep it free of UI.
- `BarbarianApp` holds the status items, the menu, the layout window and the wiring.

## Working on the real menu bar

Barbarian acts on the menu bar of the Mac it runs on, which is Pete's own.

- Hiding is reversible: quitting Barbarian brings every item back.
- Moving an item is not. macOS saves the new position in the owning app's preferences. On Pete's Mac, move only items he has agreed to, and put them back afterwards.
- Verify behavior with `--print-items` first. The `x` column and the `on`/`off` column show what the screen shows. Use `screencapture -x -R <x>,<y>,<w>,40 <file>` for a picture of the bar, where `<y>` is the top of the active display: 0 for the main display, negative for one above it.
- `open-menu` blocks Barbarian until the menu closes, and no command can close it. Run `scripts/restart-app.sh` to close it.

## Permissions

- macOS ties the Accessibility grant to the app's signature and path. `scripts/build-app.sh` always signs with the same certificate and installs to the same path, so a rebuild keeps the grant. Keep both stable.
- Without Accessibility, Barbarian can hide and reveal sections but cannot move or click other apps' items. Code that posts events checks `AccessibilityPermission.isGranted` first and must keep doing so.
- Screen Recording is optional. With it, Barbarian reads window titles, and shows each item's own image when "Show items' own icons" is on in Settings. That setting is off by default, because macOS asks people to confirm Screen Recording again from time to time for apps that capture. Without the permission, items show their app's icon and names come from the owning app or from Accessibility. Code that captures checks the setting and `ScreenRecordingPermission.isGranted` first.
- A ScreenCaptureKit capture can make macOS show Pete a screen recording alert, whether it comes from the app with the setting on, `--render-arrange --item-images`, or a test script. Render without `--item-images` unless the change is to item images, and ask Pete before capturing.
- `scripts/restart-app.sh` restarts the installed copy without building. Run `scripts/build-app.sh` first, and check the installed binary's date before testing a change in the running app.
