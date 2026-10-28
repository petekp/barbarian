#!/bin/sh
#
# Builds a universal, notarized Barbarian and its Sparkle appcast in
# .build/releases/<version>/feed. With --publish it also tags the version
# and creates the GitHub release, which is what installed copies update from.
#
# One-time setup:
# - The Developer ID Application certificate in the keychain. Set
#   BARBARIAN_RELEASE_IDENTITY to use another one's SHA-1 hash.
# - Notarization credentials:
#   xcrun notarytool store-credentials barbarian-notary
# - Sparkle's signing key in the keychain under the account `barbarian`, from
#   .build/artifacts/sparkle/Sparkle/bin/generate_keys --account barbarian
#
# Before each release, set CFBundleShortVersionString and CFBundleVersion in
# Resources/Info.plist to the new version, and give CHANGELOG.md a
# "## <version>" section. That section becomes the release notes.
#
# Usage: scripts/release.sh [--publish]

set -eu

repo=$(cd "$(dirname "$0")/.." && pwd)
publish=false
if [ "${1:-}" = "--publish" ]; then publish=true; fi
identity=${BARBARIAN_RELEASE_IDENTITY:-83FC155D3B8A2DE0858A12B029220D8D88B1250D}
notary_profile=barbarian-notary
sparkle_bin="$repo/.build/artifacts/sparkle/Sparkle/bin"
plist="$repo/Resources/Info.plist"

fail() {
    echo "$1" >&2
    exit 1
}

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist")
build_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$plist")
# Sparkle decides whether an update is newer by CFBundleVersion.
[ "$version" = "$build_version" ] || fail "CFBundleShortVersionString ($version) and CFBundleVersion ($build_version) differ."
notes=$(awk -v heading="## $version" '$0 == heading { found = 1; next } found && /^## / { exit } found { print }' "$repo/CHANGELOG.md")
[ -n "$notes" ] || fail "CHANGELOG.md has no \"## $version\" section."
if $publish; then
    [ -z "$(git -C "$repo" status --porcelain)" ] || fail "Commit local changes before publishing."
    ! git -C "$repo" rev-parse -q --verify "refs/tags/v$version" > /dev/null || fail "Tag v$version already exists."
fi

out="$repo/.build/releases/$version"
rm -rf "$out"
mkdir -p "$out/feed"

swift build --package-path "$repo" -c release --arch arm64 --arch x86_64
bin_path=$(swift build --package-path "$repo" -c release --arch arm64 --arch x86_64 --show-bin-path)
app="$out/Barbarian.app"
"$repo/scripts/assemble-app.sh" "$bin_path" "$app" "$identity" --hardened
codesign --verify --strict --deep "$app"

zip="$out/feed/Barbarian-$version.zip"
ditto -c -k --keepParent "$app" "$zip"
xcrun notarytool submit "$zip" --keychain-profile "$notary_profile" --wait
xcrun stapler staple "$app"
spctl --assess --type execute "$app"
rm "$zip"
ditto -c -k --keepParent "$app" "$zip"

# generate_appcast reads every archive in the folder and takes release notes
# from a file named like the archive.
printf '%s\n' "$notes" > "$out/feed/Barbarian-$version.md"
"$sparkle_bin/generate_appcast" --account barbarian --embed-release-notes \
    --download-url-prefix "https://github.com/petekp/barbarian/releases/download/v$version/" \
    --link https://github.com/petekp/barbarian \
    "$out/feed"
echo "SHA-256 for the Homebrew cask: $(shasum -a 256 "$zip" | cut -d ' ' -f 1)"

if $publish; then
    git -C "$repo" tag "v$version"
    git -C "$repo" push origin "v$version"
    printf '%s\n' "$notes" | gh release create "v$version" "$zip" "$out/feed/appcast.xml" \
        --repo petekp/barbarian --title "Barbarian $version" --notes-file -
fi
echo "$out/feed"
