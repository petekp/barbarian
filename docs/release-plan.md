# Release plan

The steps to take Barbarian from a personal tool to a public 0.1.0 release. The repo is already public at github.com/petekp/barbarian. Nothing has been released yet.

## 1. Decisions for Pete

| Decision | Recommendation | Why |
|---|---|---|
| License | MIT | Short, permissive and common for Mac utilities. The repo has no license today, so nobody may legally reuse the code. |
| How people install it | A notarized zip on GitHub Releases, then a Homebrew cask in Pete's own tap | Notarization lets macOS open the app without a warning. The official Homebrew cask repo expects an app with some following, and a personal tap needs none. |
| Updates | None in 0.1.0. Add Sparkle in a later release | Sparkle adds a dependency, a signing key and an appcast feed. Early users can update by hand or with Homebrew. |
| Version | 0.1.0 | The Info.plist says 0.1. Use three parts so tags and casks sort cleanly. |

## 2. Make the app safe and solid for strangers

1. **Limit the command channel to development builds.** Any process on the Mac can post the distributed notification that `--command` uses. `open-item` makes Barbarian, which holds Accessibility permission, move and click menu bar items for that process. Compile the receiver only into debug builds, or check that the sender is Barbarian's own binary.
2. **Verify the unverified features with a real pointer and Accessibility.** `docs/status.md` lists them. The release blockers are dropping items and dividers in the Arrange panel, the hot keys, hover reveal, auto-rehide, launch at login and the first launch on a clean account. Run them in a Tart VM on macOS 15 and macOS 26, so Pete's own menu bar is not touched.
3. **Check the first run.** On a clean account, the permission prompts, the Settings window and the README must agree on what Barbarian needs and why.
4. **Remove or hide the development flags from the release build:** `--print-items`, `--render-arrange` and `--render-settings`. Keep them in debug builds, where agents use them.

## 3. Update the repo

1. Add `LICENSE`.
2. Rewrite `README.md` for people who will download the app:
   - A screenshot of the menu bar and one of the Arrange panel.
   - Install from the latest release or with `brew install --cask`.
   - What each permission does, and that Screen Recording is optional.
   - A privacy line: Barbarian makes no network connections and collects nothing.
   - Build from source, as a short section at the end.
3. Let contributors build. `scripts/build-app.sh` defaults to Pete's certificate hash. Fall back to ad-hoc signing when `BARBARIAN_SIGNING_IDENTITY` is unset, and note that macOS then asks for Accessibility again after each rebuild.
4. Reword the personal framing. `AGENTS.md` speaks of "Pete's own" menu bar, and `docs/feature-scope.md` calls Barbarian a personal tool. Keep the guidance and address it to whoever runs the build.
5. Add `CHANGELOG.md` with the 0.1.0 entry.
6. Optional: issue templates for bugs, asking for the macOS version, the display setup and `--print-items` output.

## 4. Build the release

Add `scripts/release.sh`. It should do these steps in order:

1. Build a universal binary, arm64 and x86_64, in release configuration. macOS 15 still runs on Intel Macs.
2. Sign with the Developer ID Application certificate, with the hardened runtime and a secure timestamp. That certificate is already in Pete's keychain.
3. Notarize with `xcrun notarytool submit --wait`, then staple the ticket.
4. Zip the app with `ditto -c -k --keepParent`, and print its SHA-256 for the cask.
5. Tag the version and create the GitHub release with `gh release create`, attaching the zip.

Pete has to store notarization credentials once with `xcrun notarytool store-credentials`. That needs his Apple ID and an app-specific password, so only he can do it.

CI that runs `swift test` on each push is worth adding later. GitHub Actions changes need Pete's approval case by case.

## 5. Release

1. Run the release script and check the zip on a clean VM: it opens without a Gatekeeper warning, asks for Accessibility, and hides items.
2. Publish the GitHub release with notes written for users.
3. Create the `petekp/homebrew-tap` repo with a `barbarian` cask that points at the release zip.
4. Announce wherever Pete chooses.
