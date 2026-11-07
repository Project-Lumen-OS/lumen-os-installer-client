#!/bin/bash
# Builds the macOS app (release, arm64 + x86_64) into macos/dist, with the Lumen OS installer/ in its Resources.
#   bash macos/build_app.sh          "Lumen Installer.app": for users, real projectors only
#   bash macos/build_app.sh --dev    "Lumen Installer Dev.app": also the demo projector, self-tests and screenshots
# The installer comes from scripts/get_installer.sh ($LUMEN_OS_DIR, or Project-Lumen-OS/lumen-os at $LUMEN_OS_REF).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
DEV=0
[ "${1-}" = --dev ] && DEV=1
INSTALLER=$(bash "$ROOT/scripts/get_installer.sh")
if [ "$DEV" = 1 ]; then
  NAME="Lumen Installer Dev"; ID=org.lumen.installer.dev; FLAGS=(-Xswiftc -DLUMEN_DEV); SCRATCH=.build-dev
else
  NAME="Lumen Installer"; ID=org.lumen.installer; FLAGS=(); SCRATCH=.build
fi
APP="$HERE/dist/$NAME.app"
cd "$HERE"
swift build -c release --arch arm64 --arch x86_64 --scratch-path "$SCRATCH" ${FLAGS[@]+"${FLAGS[@]}"}
BIN=$(swift build -c release --arch arm64 --arch x86_64 --scratch-path "$SCRATCH" ${FLAGS[@]+"${FLAGS[@]}"} --show-bin-path)/LumenInstaller
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$NAME"
rsync -a --exclude tools/ "$INSTALLER/" "$APP/Contents/Resources/installer/"
[ "$DEV" = 1 ] && cp -R "$ROOT/shared/sim" "$APP/Contents/Resources/sim"
cp "$ROOT/assets/lumen_logo.png" "$APP/Contents/Resources/lumen_logo.png"
ICONSET=$(mktemp -d)/AppIcon.iconset
swift tools/make_icon.swift "$ROOT/assets/lumen_logo.png" "$ICONSET" && iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
VERSION=0.1.0
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>$ID</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDevelopmentRegion</key><string>ru</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "built: $APP"
