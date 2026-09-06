#!/bin/sh
# Build a distribution copy of Quibble.
#
# This is NOT the daily development install. It uses Config/Distribution.xcconfig,
# which clears the checkout-specific models path and asks for Developer ID signing,
# so the result is a bundle that behaves correctly on someone else's Mac.
#
# Notarization needs your Apple credentials and is therefore left to you; the
# commands are printed at the end rather than run.
set -eu

staging="${PWD}/.build/release-staging"
app="${staging}/Quibble.app"

: "${DEVELOPER_DIR:=/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

# The Metal toolchain override is machine-specific. Pass TOOLCHAIN= to opt out,
# or set it to your own identifier. See Docs/Setup/METAL-TOOLCHAIN.md.
toolchain_args=""
if [ -n "${TOOLCHAIN-}" ]; then
    toolchain_args="-toolchain ${TOOLCHAIN}"
fi

echo "Building into ${staging}"
# shellcheck disable=SC2086
xcodebuild \
    -project Quibble.xcodeproj -scheme Quibble -configuration Release \
    -xcconfig Config/Distribution.xcconfig \
    -derivedDataPath DerivedData -clonedSourcePackagesDirPath Inference/.build \
    -destination 'platform=macOS,arch=arm64' \
    ${toolchain_args} \
    CONFIGURATION_BUILD_DIR="${staging}" build

echo
echo "Verifying signature"
codesign --verify --deep --strict --verbose=2 "${app}"

echo
echo "Checking that no checkout path leaked into the bundle"
models_path=$(/usr/libexec/PlistBuddy -c 'Print :QuibblePrototypeModelsPath' \
    "${app}/Contents/Info.plist" 2>/dev/null || true)
if [ -n "${models_path}" ]; then
    echo "FAIL: QuibblePrototypeModelsPath is '${models_path}'; it must be empty in a" >&2
    echo "      distribution build so the app falls back to Application Support." >&2
    exit 1
fi
echo "OK: models path is empty; the app will use Application Support."

archive="${PWD}/.build/Quibble.zip"
/usr/bin/ditto -c -k --keepParent "${app}" "${archive}"

cat <<NOTES

Built and verified: ${app}
Archive for notarization: ${archive}

Notarization needs your own credentials, so run these yourself:

  xcrun notarytool submit "${archive}" \\
    --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID --password APP_SPECIFIC_PASSWORD \\
    --wait

  xcrun stapler staple "${app}"
  spctl --assess --type execute --verbose=2 "${app}"

A development-signed build is not a release. Verify a clean install and an
update on a Mac that has never run Quibble before calling this shippable.
NOTES
