#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-${VERSION:-0.1.0}}"
CONFIGURATION="${2:-${CONFIGURATION:-release}}"
CREATE_DMG="${CREATE_DMG:-1}"

APP_DISPLAY_NAME="Better Battery"
EXECUTABLE_NAME="Battary"
BUNDLE_ID="dev.sayrrexe.BetterBattery"
MIN_SYSTEM_VERSION="13.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$EXECUTABLE_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
MASCOT_ASSETS="$ROOT_DIR/Assets/Mascots"
APP_ICONSET="$DIST_DIR/AppIcon.iconset"
APP_ICON="$APP_RESOURCES/AppIcon.icns"
DMG_STAGING="$DIST_DIR/dmg"
DMG_STAGED_APP="$DMG_STAGING/$APP_DISPLAY_NAME.app"
DMG_PATH="$DIST_DIR/Better-Battery-v$VERSION-macOS.dmg"
DMG_RW_PATH="$DIST_DIR/Better-Battery-v$VERSION-macOS-rw.dmg"
DMG_MOUNT_POINT="/Volumes/$APP_DISPLAY_NAME"
SWIFT_BUILD_FLAGS=(--configuration "$CONFIGURATION" --disable-sandbox)

export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/clang-module-cache"

mkdir -p "$CLANG_MODULE_CACHE_PATH" "$DIST_DIR"

swift build "${SWIFT_BUILD_FLAGS[@]}"
BUILD_BINARY="$(swift build "${SWIFT_BUILD_FLAGS[@]}" --show-bin-path)/$EXECUTABLE_NAME"

rm -rf "$APP_BUNDLE" "$APP_ICONSET" "$DMG_STAGING"
mkdir -p "$APP_MACOS" "$APP_RESOURCES/Mascots"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

copy_mascot_assets() {
  if [[ ! -d "$MASCOT_ASSETS" ]]; then
    return
  fi

  find "$MASCOT_ASSETS" -maxdepth 1 -type f -name "*.png" -exec cp {} "$APP_RESOURCES/Mascots/" \;
}

generate_app_icon() {
  local source_icon="$MASCOT_ASSETS/cat-avatar.png"

  if [[ ! -f "$source_icon" ]]; then
    return
  fi

  rm -rf "$APP_ICONSET"
  mkdir -p "$APP_ICONSET"

  sips -z 16 16 "$source_icon" --out "$APP_ICONSET/icon_16x16.png" >/dev/null
  sips -z 32 32 "$source_icon" --out "$APP_ICONSET/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$source_icon" --out "$APP_ICONSET/icon_32x32.png" >/dev/null
  sips -z 64 64 "$source_icon" --out "$APP_ICONSET/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$source_icon" --out "$APP_ICONSET/icon_128x128.png" >/dev/null
  sips -z 256 256 "$source_icon" --out "$APP_ICONSET/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$source_icon" --out "$APP_ICONSET/icon_256x256.png" >/dev/null
  sips -z 512 512 "$source_icon" --out "$APP_ICONSET/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$source_icon" --out "$APP_ICONSET/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$source_icon" --out "$APP_ICONSET/icon_512x512@2x.png" >/dev/null

  iconutil -c icns "$APP_ICONSET" -o "$APP_ICON"
  rm -rf "$APP_ICONSET"
}

write_info_plist() {
  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
}

clear_bundle_metadata() {
  local bundle_path="$1"

  xattr -cr "$bundle_path"
  if command -v dot_clean >/dev/null 2>&1; then
    dot_clean -m "$bundle_path"
  fi
  if command -v SetFile >/dev/null 2>&1; then
    SetFile -a b "$bundle_path"
  fi
}

sign_app() {
  clear_bundle_metadata "$APP_BUNDLE"
  codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
  clear_bundle_metadata "$APP_BUNDLE"
}

create_dmg() {
  rm -f "$DMG_PATH" "$DMG_RW_PATH"
  mkdir -p "$DMG_STAGING"
  ditto --noextattr --norsrc "$APP_BUNDLE" "$DMG_STAGED_APP"
  clear_bundle_metadata "$DMG_STAGED_APP"
  ln -s /Applications "$DMG_STAGING/Applications"
  hdiutil create -volname "$APP_DISPLAY_NAME" -srcfolder "$DMG_STAGING" -ov -format UDRW -fs HFS+ "$DMG_RW_PATH" >/dev/null
  if [[ -d "$DMG_MOUNT_POINT" ]]; then
    hdiutil detach "$DMG_MOUNT_POINT" >/dev/null 2>&1 || true
  fi
  hdiutil attach "$DMG_RW_PATH" -nobrowse -readwrite >/dev/null
  clear_bundle_metadata "$DMG_MOUNT_POINT/$APP_DISPLAY_NAME.app"
  hdiutil detach "$DMG_MOUNT_POINT" >/dev/null
  hdiutil convert "$DMG_RW_PATH" -format UDZO -o "$DMG_PATH" >/dev/null
  rm -f "$DMG_RW_PATH"
  rm -rf "$DMG_STAGING"
  clear_bundle_metadata "$APP_BUNDLE"
}

copy_mascot_assets
generate_app_icon
write_info_plist
sign_app

if [[ "$CREATE_DMG" == "1" ]]; then
  create_dmg
fi

sleep 1
clear_bundle_metadata "$APP_BUNDLE"

echo "$APP_BUNDLE"
if [[ "$CREATE_DMG" == "1" ]]; then
  echo "$DMG_PATH"
fi
