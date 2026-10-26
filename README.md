# Barbarian

A menu bar manager for macOS 15 and 26. It hides the menu bar items you rarely use, keeps every item one click away, and lets you rearrange them.

## Install

```sh
scripts/build-app.sh
open ~/Applications/Barbarian.app
```

Then allow Barbarian in System Settings > Privacy & Security > Accessibility. Hiding works without it. Opening items that do not fit, and arranging from Barbarian's window, need it.

## Use

Barbarian adds an icon and two dividers to the menu bar. Items right of the ‹ divider are shown. Items between the « and ‹ dividers are hidden. Items left of « stay hidden until you ask for all of them.

| To | Do |
|---|---|
| Show hidden items | Click Barbarian's icon, press Control-Option-Command-B, or rest the pointer on the empty part of the menu bar |
| Show every item | Option-click Barbarian's icon |
| Open any item, even one that does not fit | Right-click Barbarian's icon or press Control-Option-Command-M, then pick the item or type its name |
| Rearrange | Choose Arrange Menu Bar… from that menu and drag items between rows. Or show every item, so both dividers are visible, and hold Command while dragging icons in the menu bar |

Hidden items hide again a few seconds after the pointer leaves the menu bar.
