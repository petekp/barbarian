#!/bin/sh
#
# Puts a built Barbarian binary, its resources and Sparkle into an app bundle
# and signs it. scripts/build-app.sh and scripts/release.sh both use it.
#
# --hardened signs with the hardened runtime and a secure timestamp, which
# notarization requires.
#
# Usage: scripts/assemble-app.sh <bin path> <bundle> <signing identity> [--hardened]

set -eu

repo=$(cd "$(dirname "$0")/.." && pwd)
bin_path=$1
bundle=$2
identity=$3
if [ "${4:-}" = "--hardened" ]; then
    sign() { codesign --force --options runtime --timestamp --sign "$identity" "$1"; }
else
    sign() { codesign --force --sign "$identity" "$1"; }
fi

rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$bundle/Contents/Frameworks"
cp "$bin_path/Barbarian" "$bundle/Contents/MacOS/Barbarian"
cp "$repo/Resources/Info.plist" "$bundle/Contents/Info.plist"
cp "$repo/Resources/AppIcon.icns" "$bundle/Contents/Resources/AppIcon.icns"

# Barbarian is not sandboxed, so Sparkle runs without its XPC services.
sparkle="$bundle/Contents/Frameworks/Sparkle.framework"
ditto "$bin_path/Sparkle.framework" "$sparkle"
rm -rf "$sparkle/XPCServices" "$sparkle/Versions/B/XPCServices"
sign "$sparkle/Versions/B/Autoupdate"
sign "$sparkle/Versions/B/Updater.app"
sign "$sparkle"
sign "$bundle"
