#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
STAGE_DIR="$DIST_DIR/dmg-root"
APP_NAME="OpenFlo"
APP_DIR="$STAGE_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
RW_DMG_PATH="$DIST_DIR/$APP_NAME-rw.dmg"
MOUNT_DIR="$DIST_DIR/dmg-mount"
RESOURCE_DIR="$ROOT_DIR/Sources/OpenFloApp/Resources"
DMG_BACKGROUND_SIZE=820
DMG_WINDOW_LEFT=120
DMG_WINDOW_TOP=48
DMG_WINDOW_RIGHT=$((DMG_WINDOW_LEFT + DMG_BACKGROUND_SIZE))
DMG_WINDOW_BOTTOM=$((DMG_WINDOW_TOP + DMG_BACKGROUND_SIZE))

cd "$ROOT_DIR"

echo "Building x86_64 slice..."
swift build -c release --arch x86_64 --product "$APP_NAME"
X64_BIN="$(swift build -c release --arch x86_64 --show-bin-path)/$APP_NAME"

echo "Building arm64 slice..."
swift build -c release --arch arm64 --product "$APP_NAME"
ARM_BIN="$(swift build -c release --arch arm64 --show-bin-path)/$APP_NAME"

rm -rf "$DIST_DIR"
mkdir -p "$STAGE_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

echo "Creating universal binary..."
lipo -create "$X64_BIN" "$ARM_BIN" \
    -output "$APP_DIR/Contents/MacOS/$APP_NAME"

chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

echo "Verifying universal binary..."
lipo "$APP_DIR/Contents/MacOS/$APP_NAME" -archs
lipo "$APP_DIR/Contents/MacOS/$APP_NAME" -verify_arch x86_64 arm64

if [ -d "$RESOURCE_DIR" ]; then
    cp -R "$RESOURCE_DIR"/. "$APP_DIR/Contents/Resources/"
fi

ICON_PNG="$RESOURCE_DIR/OpenFloClosed.png"
OPEN_ICON_PNG="$RESOURCE_DIR/OpenFloOpen.png"
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

BACKGROUND_DIR="$STAGE_DIR/.background"
BACKGROUND_PNG="$BACKGROUND_DIR/OpenFloDMGBackground.png"
mkdir -p "$BACKGROUND_DIR"

if command -v sips >/dev/null 2>&1 && [ -f "$OPEN_ICON_PNG" ]; then
    sips -z "$DMG_BACKGROUND_SIZE" "$DMG_BACKGROUND_SIZE" "$OPEN_ICON_PNG" --out "$BACKGROUND_PNG" >/dev/null
elif [ -f "$OPEN_ICON_PNG" ]; then
    cp "$OPEN_ICON_PNG" "$BACKGROUND_PNG"
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
    <string>0.7.0</string>
    <key>CFBundleVersion</key>
    <string>7</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

ln -s /Applications "$STAGE_DIR/Applications"

rm -f "$DMG_PATH" "$RW_DMG_PATH"
rm -rf "$MOUNT_DIR"

echo "Creating read-write DMG..."
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE_DIR" \
    -ov \
    -fs HFS+ \
    -format UDRW \
    "$RW_DMG_PATH"

if command -v osascript >/dev/null 2>&1 && [ -f "$BACKGROUND_PNG" ]; then
    mkdir -p "$MOUNT_DIR"

    echo "Mounting DMG to customize Finder layout..."
    hdiutil attach "$RW_DMG_PATH" -readwrite -noverify -noautoopen -mountpoint "$MOUNT_DIR" >/dev/null

    cleanup_mount() {
        hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
    }

    trap cleanup_mount EXIT

    osascript <<APPLESCRIPT
set dmgFolderAlias to POSIX file "$MOUNT_DIR" as alias
set backgroundAlias to POSIX file "$MOUNT_DIR/.background/OpenFloDMGBackground.png" as alias
tell application "Finder"
    set dmgFolder to folder dmgFolderAlias
    open dmgFolder
    set dmgWindow to container window of dmgFolder
    set current view of dmgWindow to icon view
    set toolbar visible of dmgWindow to false
    set statusbar visible of dmgWindow to false
    set the bounds of dmgWindow to {$DMG_WINDOW_LEFT, $DMG_WINDOW_TOP, $DMG_WINDOW_RIGHT, $DMG_WINDOW_BOTTOM}
    set viewOptions to the icon view options of dmgWindow
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set background picture of viewOptions to backgroundAlias
    set position of item "$APP_NAME.app" of dmgFolder to {270, 448}
    set position of item "Applications" of dmgFolder to {550, 448}
    update dmgFolder without registering applications
    delay 1
    close dmgWindow
end tell
APPLESCRIPT

    sync
    cleanup_mount
    trap - EXIT
    rm -rf "$MOUNT_DIR"
fi

echo "Compressing final DMG..."
hdiutil convert "$RW_DMG_PATH" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_PATH" \
    -ov >/dev/null

rm -f "$RW_DMG_PATH"

echo "Created $DMG_PATH"
