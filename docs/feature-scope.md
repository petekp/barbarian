# Feature scope

Barbarian is a macOS menu bar manager. It hides menu bar items until you ask for them. Its feature set is a cut-down version of Bartender 7.

## Platform

The app supports macOS 15 and macOS 26.

The development Mac runs macOS 15 and has a notch. Testing on macOS 26 happens in a virtual machine.

## Features

A **menu bar item** is an icon that an app places in the right side of the menu bar. The app sorts items into three sections:

- **Shown** items stay visible.
- **Hidden** items appear when you reveal them.
- **Always Hidden** items appear only on a separate, explicit reveal.

**In v1**

| Feature | Reason |
|---|---|
| Shown, Hidden and Always Hidden sections | This is the app's purpose. It needs no special permission. |
| Reveal by click, hotkey and hover | Each is cheap. Hover is the most common gesture. |
| Auto-rehide after a delay or on a click elsewhere | Without it, every reveal has to be undone by hand. |
| A menu that lists every item, including items that do not fit, and opens the one you pick | On a display with a notch, items that do not fit are dropped and cannot be clicked at all. Typing an item's name selects it, so the menu also covers keyboard access. Opening an item that is off screen needs Accessibility permission. |
| An Arrange Menu Bar panel where you drag items between sections | Command-dragging in the menu bar works only for items that are on screen, which on a full bar excludes the ones you most need to move. It needs Accessibility permission. |

**Later**

| Feature | Reason to wait |
|---|---|
| Item spacing presets: Default, Small, Tiny | Cheap, but a change takes effect only after logging out. |
| A panel below the menu bar that shows hidden items | It needs Screen Recording permission to show real item images. It pays off only when hidden items pile up. |
| Profiles: saved menu bar setups you switch between | Useful only once there is more than one setup. |
| Show an item for a while when its icon changes | It needs Screen Recording to compare images, and is hard to make reliable. |

**Cut**

| Feature | Reason |
|---|---|
| Menu bar styling: glass, tints, gradients, pill shapes | Decoration. The Liquid Glass style exists only on macOS 26. |
| Triggers that reveal items on Wi-Fi, power or microphone changes | Each condition needs its own event source. A hotkey covers the same need. |
| Custom items and widgets driven by scripts | A plugin platform, not a menu bar manager feature. SwiftBar already does this. |
| Clipboard history | A separate product. |
| Bartender Pro's Top Shelf: notch island, media controls, weather, calendar, AirDrop shelf, agent monitor | A separate product. An agent monitor would be its own project. |
| Siri, AppleScript and Shortcuts automation | No current need. One hook can be added if a need appears. |
| Spacers, text labels and emoji in the bar | They only help when the bar has many items to sort visually. |
| Item groups and a different style per Space | Low value for one user. |

## Implementation costs

These costs decided most of the calls above.

- **Hiding items is cheap.** The app adds its own invisible menu bar item and widens it. Everything to its left moves off screen. This needs no permission.
- **Moving another app's item is fragile.** macOS has no API for it. The app has to post synthetic Command-drag mouse events through the Accessibility API.
- **Showing another app's item image needs Screen Recording.** Without that permission the app can show only the owning app's icon.
- **Each trigger condition is its own subsystem.** Power, Wi-Fi and microphone use each need a separate event source.

Ice is an open-source menu bar manager that uses the same hiding approach on macOS 14 and 15. Check its license before reusing any of its code.
