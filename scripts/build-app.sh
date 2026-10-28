#!/bin/sh
#
# Builds Barbarian.app, signs it, and installs it at ~/Applications/Barbarian.app.
#
# macOS ties an Accessibility grant to the app's signature and path. Signing
# every build with the same certificate and installing to the same path keeps
# the grant across rebuilds. Set BARBARIAN_SIGNING_IDENTITY to your own
# certificate (a SHA-1 hash from `security find-identity -v -p codesigning`).
# Without a certificate in the keychain the app is signed ad hoc, and macOS
# asks for Accessibility again after each rebuild.
#
# Usage: scripts/build-app.sh [--release]

set -eu

repo=$(cd "$(dirname "$0")/.." && pwd)
configuration=debug
if [ "${1:-}" = "--release" ]; then configuration=release; fi
identity=${BARBARIAN_SIGNING_IDENTITY:-DBB4644C848E988CCF04ED55ECFAC79F7E34BEDF}
if ! security find-identity -v -p codesigning | grep -q "$identity"; then
    echo "Signing identity $identity not found; signing ad hoc." >&2
    identity=-
fi

swift build --package-path "$repo" -c "$configuration"
bin_path=$(swift build --package-path "$repo" -c "$configuration" --show-bin-path)

bundle="$repo/.build/Barbarian.app"
rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$bin_path/Barbarian" "$bundle/Contents/MacOS/Barbarian"
cp "$repo/Resources/Info.plist" "$bundle/Contents/Info.plist"
cp "$repo/Resources/AppIcon.icns" "$bundle/Contents/Resources/AppIcon.icns"

# Barbarian is not sandboxed, so Sparkle runs without its XPC services.
sparkle="$bundle/Contents/Frameworks/Sparkle.framework"
mkdir -p "$bundle/Contents/Frameworks"
ditto "$bin_path/Sparkle.framework" "$sparkle"
rm -rf "$sparkle/XPCServices" "$sparkle/Versions/B/XPCServices"
codesign --force --sign "$identity" "$sparkle/Versions/B/Autoupdate"
codesign --force --sign "$identity" "$sparkle/Versions/B/Updater.app"
codesign --force --sign "$identity" "$sparkle"
codesign --force --sign "$identity" "$bundle"

installed="$HOME/Applications/Barbarian.app"
rm -rf "$installed"
ditto "$bundle" "$installed"
echo "$installed"
