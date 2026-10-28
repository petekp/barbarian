# Release plan

The steps to take Barbarian from a personal tool to a public 0.1.0 release. The repo is already public at github.com/petekp/barbarian. Nothing has been released yet.

## 1. Decisions for Pete

| Decision | Recommendation | Why |
|---|---|---|
| License | MIT | Short, permissive and common for Mac utilities. The repo has no license today, so nobody may legally reuse the code. |
| How people install it | A notarized zip on GitHub Releases, then a Homebrew cask in Pete's own tap | Notarization lets macOS open the app without a warning. The official Homebrew cask repo expects an app with some following, and a personal tap needs none. |
| Updates | Sparkle, from 0.1.0 | Sparkle is the standard updater for Mac apps outside the App Store. It downloads, verifies and installs each update in place. Checking GitHub for a newer release and opening the download page would avoid the dependency, but people would install every update by hand. |
| Version | 0.1.0 | The Info.plist says 0.1. Use three parts so tags and casks sort cleanly. |

## 2. Make the app safe and solid for strangers

1. **Limit the command channel to development builds.** Any process on the Mac can post the distributed notification that `--command` uses. `open-item` makes Barbarian, which holds Accessibility permission, move and click menu bar items for that process. Compile the receiver only into debug builds, or check that the sender is Barbarian's own binary.
2. **Verify the unverified features with a real pointer and Accessibility.** `docs/status.md` lists them. The release blockers are dropping items and dividers in the Arrange panel, the hot keys, hover reveal, auto-rehide, launch at login and the first launch on a clean account. Run them in a Tart VM on macOS 15 and macOS 26, so Pete's own menu bar is not touched.
3. **Check the first run.** On a clean account, the permission prompts, the Settings window and the README must agree on what Barbarian needs and why.
4. **Add Sparkle.** Add the Swift package, a Check for Updates… item in the items menu, and an automatic-check setting in Settings. Embed and sign `Sparkle.framework` in `scripts/build-app.sh`. The feed URL is `https://github.com/petekp/barbarian/releases/latest/download/appcast.xml`, which always points at the newest release's asset, so no extra hosting is needed.
5. **Remove or hide the development flags from the release build:** `--print-items`, `--render-arrange` and `--render-settings`. Keep them in debug builds, where agents use them.

## 3. Update the repo

1. Add `LICENSE`.
2. Rewrite `README.md` for people who will download the app:
   - A screenshot of the menu bar and one of the Arrange panel.
   - Install from the latest release or with `brew install --cask`.
   - What each permission does, and that Screen Recording is optional.
   - A privacy line: Barbarian's only network request is the update check against GitHub, and it collects nothing.
   - Build from source, as a short section at the end.
3. Let contributors build. `scripts/build-app.sh` defaults to Pete's certificate hash. Fall back to ad-hoc signing when `BARBARIAN_SIGNING_IDENTITY` is unset, and note that macOS then asks for Accessibility again after each rebuild.
4. Reword the personal framing. `AGENTS.md` speaks of "Pete's own" menu bar, and `docs/feature-scope.md` calls Barbarian a personal tool. Keep the guidance and address it to whoever runs the build.
5. Add `CHANGELOG.md` with the 0.1.0 entry.
6. Optional: issue templates for bugs, asking for the macOS version, the display setup and `--print-items` output.

## 4. Build the release

`scripts/release.sh` does these steps in order. Its header lists the one-time setup and what to change before each release.

1. Build a universal binary, arm64 and x86_64, in release configuration. macOS 15 still runs on Intel Macs.
2. Sign with the Developer ID Application certificate, with the hardened runtime and a secure timestamp. That certificate is already in Pete's keychain.
3. Notarize with `xcrun notarytool submit --wait`, then staple the ticket.
4. Zip the app with `ditto -c -k --keepParent`, and print its SHA-256 for the cask.
5. Sign the zip and write `appcast.xml` with Sparkle's `generate_appcast`, with the version's `CHANGELOG.md` section as release notes.
6. With `--publish`, tag the version and create the GitHub release with `gh release create`, attaching the zip and `appcast.xml`.

Two one-time setup steps:

- Pete stores notarization credentials with `xcrun notarytool store-credentials barbarian-notary`. That needs his Apple ID and an app-specific password, so only he can do it.
- Sparkle's `generate_keys` makes the update signing key and keeps the private half in Pete's login keychain. The public half goes in `Info.plist` as `SUPublicEDKey`. Losing the private key means existing installs can no longer verify updates, so back it up with `generate_keys -x`.

CI that runs `swift test` on each push is worth adding later. GitHub Actions changes need Pete's approval case by case.

## 5. Release

1. Run the release script and check the zip on a clean VM: it opens without a Gatekeeper warning, asks for Accessibility, and hides items.
2. Publish the GitHub release with notes written for users.
3. Create the `petekp/homebrew-tap` repo with a `barbarian` cask that points at the release zip, marked `auto_updates true` since Sparkle updates the app.
4. Announce wherever Pete chooses.
