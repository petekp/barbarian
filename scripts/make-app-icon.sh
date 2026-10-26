#!/bin/sh
#
# Draws the app icon from the menu bar axe and writes Resources/AppIcon.icns.
# Run it after changing AppIconRenderer or BattleAxeIcon.

set -eu

repo=$(cd "$(dirname "$0")/.." && pwd)
iconset="$repo/.build/AppIcon.iconset"

swift build --package-path "$repo"
rm -rf "$iconset"
"$(swift build --package-path "$repo" --show-bin-path)/Barbarian" --render-app-icon "$iconset"
iconutil --convert icns --output "$repo/Resources/AppIcon.icns" "$iconset"
echo "$repo/Resources/AppIcon.icns"
