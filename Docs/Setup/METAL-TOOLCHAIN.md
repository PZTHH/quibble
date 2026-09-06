# Metal Toolchain setup on this Mac

Checked 2026-09-05 with Xcode 26.6 (17F113). Recheck after changing Xcode versions.

The normal Xcode component downloader stalled at “Beginning asset download”. The user downloaded Apple's matching Metal Toolchain 26.6 (17F109) archive directly. Its size and SHA-256 matched Apple's local MobileAsset catalog:

- Size: 687,865,856 bytes.
- SHA-256: `52b695754914d150d630fe149cacc76a6d72052d6a62dab1f2b92f3e68267a56`.
- [Apple CDN archive](https://updates.cdn-apple.com/2026MobileAssets/mobileassets/022-22264/722AB304-567A-4611-A7CA-1A94FA951B0B/com_apple_MobileAsset_MetalToolchain/78ED9FD0-8B39-4EEF-B0EE-67013D77BE16.aar).
- Catalog: `/System/Library/AssetsV2/com_apple_MobileAsset_MetalToolchain/com_apple_MobileAsset_MetalToolchain.xml`.

Apple's `aa patch` utility unpacked the archive into `.build/MetalToolchain-17F109.asset`, using the archive key provided in the catalog. The included disk image was mounted read-only. Its original `Metal.xctoolchain` was copied to `~/Library/Developer/Toolchains/Metal.xctoolchain`, and the image was unmounted. The compiler's code signature verifies and `metal --version` reports `32023.883`.

Xcode's component importer rejected the raw asset because it lacks `ExportMetadata.plist`. This is therefore a manually selected user toolchain, **not** a completed installation through Xcode Components. No Xcode binaries, Apple version metadata, or system permission databases were edited.

Select the installed toolchain explicitly when building:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Quibble.xcodeproj -scheme Quibble -configuration Release \
  -derivedDataPath DerivedData -clonedSourcePackagesDirPath Inference/.build \
  -destination 'platform=macOS,arch=arm64' \
  -toolchain com.apple.dt.toolchain.Metal.32023.883 build
```

Observed: Xcode resolves this override and invokes the compiler in the user toolchains folder for Quibble's MLX shaders. `xcrun --find metal` still resolves the default Xcode launcher, so that command alone does not establish whether the build override works. Full application build and runtime results are tracked in [phase 1 report](../History/PHASE-1.md).

For a standard installation, Apple's supported paths are Xcode Settings → Components, `xcodebuild -downloadComponent MetalToolchain`, or importing a bundle produced by `-downloadComponent MetalToolchain -exportPath …`. The local CLI documents `-importComponent MetalToolchain -importPath …`. See [Apple's additional component instructions](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components), read 2026-09-05.
