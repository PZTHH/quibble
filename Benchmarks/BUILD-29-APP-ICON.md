# Build 29 — approved quotation icon

Verified 2026-09-06 on this development Mac.

## Integration

- Inspected only `Quibble-iOS-Default-1024x1024@1x.png` from the user’s `~/Documents/Quibble Exports` directory.
- Found the corresponding original `~/Documents/Quibble.icon` project beside it. Copied both project files byte-for-byte to `App/Resources/Quibble.icon`, preserving the user’s composition and appearance settings. Original files were not modified.
- Set the app icon name to `Quibble` in the existing shared signing configuration. The filesystem-synchronized App group includes the native icon source without a manually maintained Xcode file reference.
- Reused the original quotation layer in `Branding.xcassets/QuibbleMark.imageset`, marked as a template. The idle menu bar and setup header use this asset; the recording microphone indicator remains. Display frames account for the transparent padding in the supplied layer without modifying its pixels.
- Added the approved default export to the README and updated design records to reflect the user’s selected quotation direction. No new imagery was generated.

## Verification

- Release Xcode build completed with **BUILD SUCCEEDED**, exit 0: `.build/build29.log`. Asset compilation includes `Branding.xcassets`, `ModelIcons.xcassets`, and `Quibble.icon`.
- The generated app contains `Quibble.icns` and `Assets.car`; both `CFBundleIconName` and `CFBundleIconFile` resolve to `Quibble`.
- Staged and installed app bundles passed `codesign --verify --deep --strict --verbose=2`. Installed `CFBundleVersion` is **29** at the stable daily path with the existing development identity.
- Installation followed a fresh Home ready-state check and UI quit. The app reopened successfully; the setup guide still reports permissions/models ready, and its quotation header was visually inspected.
- Finder displays the installed quotation-mark app icon. The system Dock surface could not be inspected through the UI tool (timeout); no Dock-specific visual claim is made. Menu-bar sizing is configured in the running app, but no separate status-bar screenshot was captured.
- No audio, model, insertion, or shortcut logic changed; no additional ASR run or model download was needed. Existing compiler warnings concern unrelated legacy Keychain APIs and App Intents metadata.

This is a development-signed update, not publication. No GitHub upload occurred.
