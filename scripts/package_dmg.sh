#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
STAGE_DIR="$DIST_DIR/dmg-root"
APP_NAME="OpenFlo"
APP_DIR="$STAGE_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
RESOURCE_DIR="$ROOT_DIR/Sources/OpenFloApp/Resources"

cd "$ROOT_DIR"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"

rm -rf "$DIST_DIR"
mkdir -p "$STAGE_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
if [ -d "$RESOURCE_DIR" ]; then
    cp -R "$RESOURCE_DIR"/. "$APP_DIR/Contents/Resources/"
fi

ICON_PNG="$RESOURCE_DIR/OpenFloClosed.png"
ICONSET_DIR="$DIST_DIR/OpenFloClosed.iconset"
if command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1 && [ -f "$ICON_PNG" ]; then
    mkdir -p "$ICONSET_DIR"
    while read -r size filename; do
        sips -z "$size" "$size" "$ICON_PNG" --out "$ICONSET_DIR/$filename" >/dev/null
    done <<'SIZES'
16 icon_16x16.png
32 icon_16x16@2x.png
32 icon_32x32.png
64 icon_32x32@2x.png
128 icon_128x128.png
256 icon_128x128@2x.png
256 icon_256x256.png
512 icon_256x256@2x.png
512 icon_512x512.png
1024 icon_512x512@2x.png
SIZES
    iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/OpenFloClosed.icns"
fi

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>OpenFlo</string>
    <key>CFBundleIdentifier</key>
    <string>org.openflo.OpenFlo</string>
    <key>CFBundleName</key>
    <string>OpenFlo</string>
    <key>CFBundleDisplayName</key>
    <string>OpenFlo</string>
    <key>CFBundleIconFile</key>
    <string>OpenFloClosed</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

ln -s /Applications "$STAGE_DIR/Applications"
rm -f "$DMG_PATH"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

echo "Created $DMG_PATH"
