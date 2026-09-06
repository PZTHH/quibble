# What Quibble would need for an updater

Retrieved: **2026-09-06**. Directional after: **2026-10-06**; recheck version-specific APIs and signing guidance before implementation. **Low-priority research only.** No dependency, key, feed, account, release, or updater was installed or configured.

## Recommendation

Use **Sparkle 2** for a future directly distributed macOS app. Start with its standard update UI and a **Check for Updates…** menu item, then offer user-controlled automatic checks. This is a proposed fit for Quibble’s native app, not an integration already tested here. Sparkle documents a SwiftUI setup through `SPUStandardUpdaterController`. [Programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/), read 2026-09-06.

The larger prerequisite is a repeatable release pipeline. Publishing source on GitHub does not create an in-app updater. GitHub Releases can host downloadable binaries; a Sparkle appcast still describes the available update, and Sparkle performs the app-side update flow. Hosting the release files on GitHub and the feed at a stable HTTPS location is one option, not a selected host or URL. [GitHub Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases), [Sparkle appcast setup](https://sparkle-project.org/documentation/#5-publish-your-appcast), read 2026-09-06.

## Current starting point

Inspected the local working tree on 2026-09-06; Git has no commit yet, so there is no immutable revision to cite.

| Local evidence | Implication |
| --- | --- |
| [Signing configuration](../Config/Signing.xcconfig): `Apple Development`, stable bundle ID/team, hardened runtime enabled, sandbox disabled | This is development signing. Keep it stable for the current installation; create a deliberate distribution configuration rather than changing the daily build opportunistically. |
| [Info.plist](../Config/Info.plist), [project generator](../Scripts/generate-project.py), [Xcode project](../Quibble.xcodeproj/project.pbxproj), and package manifests | No configured Sparkle dependency, appcast URL, or public update-signing key was found in these integration points. Version/build settings already exist. |
| [Info.plist](../Config/Info.plist) defaults model storage to the checkout; [README](../README.md) describes the development installation | A stable distribution location and an application-managed model-storage migration are still release work. Models should stay separate from app update archives. |
| [Identity checker](../Scripts/check-update-identity.py) | It compares two signed builds and checks the updated app against the old designated requirement. Its own output explicitly does not claim permission retention. |

## Release requirements

| Requirement | Source, read 2026-09-06 |
| --- | --- |
| Sign the distribution with **Developer ID Application**, retain hardened runtime and secure signing timestamps, and notarize it. Apple provides Xcode distribution and `notarytool` submission; `stapler` attaches the ticket. Apple Development signing is not the intended distribution identity. | [Apple Developer ID](https://developer.apple.com/developer-id/), [notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) |
| Embed/sign Sparkle correctly. Use HTTPS and a separate EdDSA/Ed25519 archive signature; embed only its public key as `SUPublicEDKey`. Sparkle’s key generator stores the private key in the login Keychain. Keep private signing material off the hosting server and out of Git. | [Sparkle basic setup and security](https://sparkle-project.org/documentation/#3-segue-for-security-concerns) |
| Configure a real `SUFeedURL`; increase `CFBundleVersion` for each newer build. Preserve framework symlinks when packaging. Generate the appcast from the final archives so the signature, version, size, release notes, and download reference agree. | [Sparkle publishing](https://sparkle-project.org/documentation/publishing/) |

Keep Apple signing keys, notarization credentials, and the Sparkle private key outside the repository and logs, using Keychain or an appropriately restricted future release-secret store. Record backup/recovery ownership. Apple code signing and Sparkle archive signing serve different checks; HTTPS alone is not an archive signature. Revisit Sparkle’s documented key-rotation constraints before changing signing material. [Sparkle security/key rotation](https://sparkle-project.org/documentation/#rotating-signing-keys), read 2026-09-06.

## Small implementation sequence

The following is proposed Quibble engineering work:

1. **Make two reproducible distribution builds.** Choose the intended installed app location, preserve bundle ID/team, define monotonically increasing build numbers, and finish the model/data migration plan. Archive, sign, notarize, and validate the actual distributable with its frameworks and notices.
2. **Add a pinned Sparkle release.** Use its standard UI and menu validation. Connect installation/relaunch deferral to Quibble’s recording, processing, and inserting states; checking or downloading an update must not interrupt dictation. Preserve user update preferences. Avoid a custom downloader or replacement mechanism.
3. **Create a dedicated test feed and final-artifact signing workflow.** Choose HTTPS hosting, validate download access, and publish the feed only after its referenced archive is available. Keep previous signed artifacts and a documented recovery procedure. Defer delta updates and elaborate release channels until full-archive updates pass.
4. **Test a real installed-location update.** Grant microphone/Accessibility to the older signed build, use it, update to the newer build, and verify recording, both shortcuts, and insertion without resetting permissions. Check the development-to-distribution transition separately; same bundle/team and Xcode sign-in do not prove its permission behavior. Preserve vocabulary, modes, model paths/downloads, and opted-in history. Treat session-only history and pending drafts explicitly before relaunch.
5. **Exercise failure paths before a beta.** Test offline/failed downloads, corrupt or incorrectly signed archives, cancelled installation, active dictation, unavailable install location, unsupported OS, and an interrupted migration. A failed update must leave a usable installed app or a tested recovery path. Validate a clean install and update on another Mac/user account, not only from DerivedData.

The test requirement follows Quibble’s existing [development invariants](../AGENTS.md) and [identity checker](../Scripts/check-update-identity.py); it is not a promise that Sparkle alone preserves TCC permissions or migrates application data. Read 2026-09-06.

## Open prerequisites

- **Unconfirmed:** access to a usable Developer ID certificate and notarization account. Only configuration was inspected; credentials and entitlements were not exercised. Verify through the chosen Apple distribution workflow later.
- **Unchosen:** release/feed hosting, signing-key owner/backups, update preference defaults, and the supported migration from this development installation. No release URL is invented here.
- **Untested:** Sparkle with Quibble’s frameworks, runtime behavior, relaunch guard, migrations, and actual permission retention. No updater or notarization test ran during this research.

Keep this behind current reliability work. The next updater-specific task, when prioritized, is a signed distribution-build/release checklist and two-build test fixture—not publishing an automatic update to current users.
