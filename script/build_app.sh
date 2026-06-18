#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-${VERSION:-0.1.0}}"
CONFIGURATION="${2:-${CONFIGURATION:-release}}"
CREATE_DMG="${CREATE_DMG:-1}"
DMGBUILD_VERSION="${DMGBUILD_VERSION:-1.6.7}"

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
MASCOT_ASSETS="$ROOT_DIR/Sources/Battary/Resources/Mascots"
DMG_BACKGROUND="$ROOT_DIR/Assets/Installer/dmg-background.png"
DMG_SETTINGS="$ROOT_DIR/script/dmg_settings.py"
APP_ICONSET="$DIST_DIR/AppIcon.iconset"
APP_ICON="$APP_RESOURCES/AppIcon.icns"
DMG_STAGING="$DIST_DIR/dmg"
DMG_PATH="$DIST_DIR/Better-Battery-v$VERSION-macOS.dmg"
DMGBUILD_VENV="${DMGBUILD_VENV:-$ROOT_DIR/.build/dmgbuild-venv}"
SWIFT_BUILD_FLAGS=(--configuration "$CONFIGURATION" --disable-sandbox)

export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/clang-module-cache"

mkdir -p "$CLANG_MODULE_CACHE_PATH" "$DIST_DIR"

swift build "${SWIFT_BUILD_FLAGS[@]}"
BUILD_DIR="$(swift build "${SWIFT_BUILD_FLAGS[@]}" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$EXECUTABLE_NAME"
BUILD_RESOURCE_BUNDLE="$BUILD_DIR/${EXECUTABLE_NAME}_${EXECUTABLE_NAME}.bundle"

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

copy_swiftpm_resource_bundle() {
  if [[ ! -d "$BUILD_RESOURCE_BUNDLE" ]]; then
    return
  fi

  cp -R "$BUILD_RESOURCE_BUNDLE" "$APP_RESOURCES/"
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
  xattr -d -r com.apple.FinderInfo "$bundle_path" 2>/dev/null || true
  xattr -d -r com.apple.ResourceFork "$bundle_path" 2>/dev/null || true
  xattr -d -r 'com.apple.fileprovider.fpfs#P' "$bundle_path" 2>/dev/null || true
}

sign_app() {
  clear_bundle_metadata "$APP_BUNDLE"
  codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
  clear_bundle_metadata "$APP_BUNDLE"
}

resolve_dmgbuild() {
  if [[ -n "${DMGBUILD_BIN:-}" ]]; then
    if command -v "$DMGBUILD_BIN" >/dev/null 2>&1; then
      command -v "$DMGBUILD_BIN"
      return
    fi

    if [[ -x "$DMGBUILD_BIN" ]]; then
      printf '%s\n' "$DMGBUILD_BIN"
      return
    fi

    echo "DMGBUILD_BIN is set but is not executable: $DMGBUILD_BIN" >&2
    exit 1
  fi

  local dmgbuild_bin="$DMGBUILD_VENV/bin/dmgbuild"
  if [[ -x "$dmgbuild_bin" ]]; then
    printf '%s\n' "$dmgbuild_bin"
    return
  fi

  local python_bin
  python_bin="$(resolve_dmgbuild_python)"
  if [[ -z "$python_bin" ]]; then
    echo "Python >=3.10 is required to install dmgbuild==$DMGBUILD_VERSION" >&2
    exit 1
  fi

  rm -rf "$DMGBUILD_VENV"
  "$python_bin" -m venv "$DMGBUILD_VENV"
  if ! "$DMGBUILD_VENV/bin/python" -m pip --version >/dev/null 2>&1; then
    echo "pip is required in the dmgbuild virtual environment: $DMGBUILD_VENV" >&2
    exit 1
  fi

  "$DMGBUILD_VENV/bin/python" -m pip install "dmgbuild==$DMGBUILD_VERSION" >/dev/null
  printf '%s\n' "$dmgbuild_bin"
}

resolve_dmgbuild_python() {
  local candidates=()

  if [[ -n "${DMGBUILD_PYTHON_BIN:-}" ]]; then
    candidates+=("$DMGBUILD_PYTHON_BIN")
  fi

  candidates+=(python3.13 python3.12 python3.11 python3.10 python3)

  local candidate
  for candidate in "${candidates[@]}"; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" - <<'PY' >/dev/null 2>&1
import sys

raise SystemExit(0 if sys.version_info >= (3, 10) else 1)
PY
    then
      command -v "$candidate"
      return
    fi

    if [[ -x "$candidate" ]] && "$candidate" - <<'PY' >/dev/null 2>&1
import sys

raise SystemExit(0 if sys.version_info >= (3, 10) else 1)
PY
    then
      printf '%s\n' "$candidate"
      return
    fi
  done
}

create_dmg() {
  if [[ ! -f "$DMG_SETTINGS" ]]; then
    echo "DMG settings file is missing: $DMG_SETTINGS" >&2
    exit 1
  fi

  if [[ ! -f "$DMG_BACKGROUND" ]]; then
    echo "DMG background file is missing: $DMG_BACKGROUND" >&2
    exit 1
  fi

  local dmgbuild_bin
  dmgbuild_bin="$(resolve_dmgbuild)"

  local temp_dir
  local dmg_app
  local dmg_rw_path
  local dmg_mount_point
  temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/better-battery-dmg.XXXXXX")"
  dmg_app="$temp_dir/$APP_DISPLAY_NAME.app"
  dmg_rw_path="$temp_dir/Better-Battery-v$VERSION-macOS-rw.dmg"
  dmg_mount_point="$temp_dir/mount"
  ditto --noextattr --norsrc "$APP_BUNDLE" "$dmg_app"
  clear_bundle_metadata "$dmg_app"
  codesign --force --deep --sign - "$dmg_app" >/dev/null
  clear_bundle_metadata "$dmg_app"
  mkdir -p "$dmg_mount_point"

  rm -f "$DMG_PATH"
  rm -rf "$DMG_STAGING"
  "$dmgbuild_bin" \
    -s "$DMG_SETTINGS" \
    -D "app=$dmg_app" \
    -D "background=$DMG_BACKGROUND" \
    -D "app_name=$APP_DISPLAY_NAME.app" \
    -D "image_format=UDRW" \
    "$APP_DISPLAY_NAME" \
    "$dmg_rw_path"
  hdiutil attach "$dmg_rw_path" -nobrowse -readwrite -mountpoint "$dmg_mount_point" >/dev/null
  clear_bundle_metadata "$dmg_mount_point/$APP_DISPLAY_NAME.app"
  hdiutil detach "$dmg_mount_point" >/dev/null
  hdiutil convert "$dmg_rw_path" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" -ov >/dev/null
  rm -rf "$temp_dir"
  clear_bundle_metadata "$APP_BUNDLE"
}

copy_mascot_assets
copy_swiftpm_resource_bundle
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
