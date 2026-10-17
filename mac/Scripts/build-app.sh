#!/usr/bin/env bash
# Builds mac/build/AppLauncher.app from the Swift package.
#
#   Scripts/build-app.sh            # universal (arm64 + x86_64) release build, version 0.0.0
#   Scripts/build-app.sh 1.2.3      # stamps CFBundleShortVersionString/CFBundleVersion
#   UNIVERSAL=0 Scripts/build-app.sh   # native architecture only (faster on a dev machine)
#
# The bundle is ad-hoc signed so Gatekeeper lets it run after a right-click > Open.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-0.0.0}"
UNIVERSAL="${UNIVERSAL:-1}"

ARCH_FLAGS=()
if [[ "$UNIVERSAL" == "1" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

# macOS ships bash 3.2, where "${EMPTY[@]}" trips `set -u`; this expansion is safe there too.
echo "==> swift build -c release ${ARCH_FLAGS[*]:-}"
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --product AppLauncher

BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --product AppLauncher --show-bin-path)"
APP="build/AppLauncher.app"

echo "==> assembling $APP (version $VERSION)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/AppLauncher" "$APP/Contents/MacOS/AppLauncher"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ -d "$BIN_DIR/AppLauncher_AppLauncher.bundle" ]]; then
  cp -R "$BIN_DIR/AppLauncher_AppLauncher.bundle" "$APP/Contents/Resources/"
fi

echo "==> codesign (ad-hoc)"
codesign --force --deep --sign - "$APP"

echo "==> done: $(pwd)/$APP"
file "$APP/Contents/MacOS/AppLauncher"
