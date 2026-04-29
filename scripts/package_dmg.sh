#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/SalaryDance.xcodeproj}"
SCHEME="${SCHEME:-SalaryDance}"
CONFIGURATION="${CONFIGURATION:-Release}"
PRODUCT_NAME="${PRODUCT_NAME:-SalaryDance}"
APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-薪动}"
APP_BUNDLE_NAME="${APP_BUNDLE_NAME:-薪动.app}"
INFO_PLIST="${INFO_PLIST:-$ROOT_DIR/SalaryDance/Info.plist}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/build/package-derived-data}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
STAGING_DIR="$DIST_DIR/dmg-root"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST" 2>/dev/null || echo '1.0')"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST" 2>/dev/null || echo '1')"
DMG_NAME="${DMG_NAME:-SalaryDance-${VERSION}-${BUILD_NUMBER}}"
DMG_PATH="$DIST_DIR/${DMG_NAME}.dmg"
RW_DMG_PATH="$DIST_DIR/${DMG_NAME}-rw.dmg"

BUILT_APP="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$PRODUCT_NAME.app"
PACKAGED_APP="$STAGING_DIR/$APP_BUNDLE_NAME"

DMG_ICON_SIZE="${DMG_ICON_SIZE:-128}"
DMG_TEXT_SIZE="${DMG_TEXT_SIZE:-13}"
DMG_WINDOW_WIDTH="${DMG_WINDOW_WIDTH:-660}"
DMG_WINDOW_HEIGHT="${DMG_WINDOW_HEIGHT:-330}"
DMG_WINDOW_BOUNDS="${DMG_WINDOW_BOUNDS:-{180, 120, 840, 450}}"
DMG_APP_ICON_POSITION="${DMG_APP_ICON_POSITION:-{190, 170}}"
DMG_APPLICATIONS_ICON_POSITION="${DMG_APPLICATIONS_ICON_POSITION:-{470, 170}}"
MOUNT_PATH=""

cleanup() {
  if [[ -n "$MOUNT_PATH" && -d "$MOUNT_PATH" ]]; then
    hdiutil detach "$MOUNT_PATH" -quiet || true
  fi
}

trap cleanup EXIT

detach_existing_dmg_mounts() {
  local mounts=()

  while IFS= read -r mount_path; do
    [[ -n "$mount_path" ]] && mounts+=("$mount_path")
  done < <(
    hdiutil info | awk -v image_path="$DMG_PATH" '
      /^image-path[[:space:]]*:/ {
        current = $0
        sub(/^[^:]+:[[:space:]]*/, "", current)
        matched = (current == image_path)
      }
      matched && index($0, "/Volumes/") {
        print substr($0, index($0, "/Volumes/"))
      }
    '
  )

  if (( ${#mounts[@]} == 0 )); then
    return
  fi

  echo "==> Detaching existing DMG mounts"
  for mount_path in "${mounts[@]}"; do
    hdiutil detach "$mount_path" -quiet || true
  done
}

create_applications_link() {
  rm -f "$STAGING_DIR/Applications"
  ln -s /Applications "$STAGING_DIR/Applications"
}

style_dmg_window() {
  echo "==> Styling DMG window"
  rm -f "$MOUNT_PATH/.DS_Store"

  /usr/bin/osascript <<APPLESCRIPT
tell application "Finder"
  set mountedFolder to POSIX file "$MOUNT_PATH" as alias
  open mountedFolder
  delay 1

  try
    set dmgWindow to container window of mountedFolder
  on error
    set dmgWindow to front Finder window
  end try

  set current view of dmgWindow to icon view
  set toolbar visible of dmgWindow to false
  set statusbar visible of dmgWindow to false
  set bounds of dmgWindow to $DMG_WINDOW_BOUNDS

  set viewOptions to icon view options of dmgWindow
  set arrangement of viewOptions to not arranged
  set icon size of viewOptions to $DMG_ICON_SIZE
  set text size of viewOptions to $DMG_TEXT_SIZE

  set position of item "$APP_BUNDLE_NAME" of dmgWindow to $DMG_APP_ICON_POSITION
  set position of item "Applications" of dmgWindow to $DMG_APPLICATIONS_ICON_POSITION

  update mountedFolder without registering applications
  delay 2

  if (icon size of viewOptions) is not $DMG_ICON_SIZE then
    error "Finder icon size did not persist"
  end if

  close dmgWindow
end tell
APPLESCRIPT

  sync
  sleep 1
  rm -rf "$MOUNT_PATH/.fseventsd" "$MOUNT_PATH/.Trashes"

  if [[ ! -f "$MOUNT_PATH/.DS_Store" ]]; then
    echo "Finder did not create $MOUNT_PATH/.DS_Store" >&2
    exit 1
  fi
}

verify_dmg_root_contents() {
  local root_path="$1"
  local unexpected=()

  while IFS= read -r entry; do
    case "$(basename "$entry")" in
      "."|".."|".DS_Store"|"Applications"|"$APP_BUNDLE_NAME")
        ;;
      *)
        unexpected+=("$(basename "$entry")")
        ;;
    esac
  done < <(find "$root_path" -mindepth 1 -maxdepth 1 -print)

  if (( ${#unexpected[@]} > 0 )); then
    printf 'Unexpected DMG root item: %s\n' "${unexpected[@]}" >&2
    exit 1
  fi
}

echo "==> Building $SCHEME ($CONFIGURATION)"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGN_IDENTITY=- \
  build

if [[ ! -d "$BUILT_APP" ]]; then
  echo "Built app not found: $BUILT_APP" >&2
  exit 1
fi

detach_existing_dmg_mounts

echo "==> Preparing DMG contents"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "$DIST_DIR"

ditto "$BUILT_APP" "$PACKAGED_APP"
create_applications_link

verify_dmg_root_contents "$STAGING_DIR"

echo "==> Verifying ad-hoc app signature"
codesign --verify --deep --strict --verbose=2 "$PACKAGED_APP"

echo "==> Creating DMG"
rm -f "$DMG_PATH" "$RW_DMG_PATH"
hdiutil create \
  -volname "$APP_DISPLAY_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDRW \
  "$RW_DMG_PATH"

MOUNT_PATH="$(
  hdiutil attach "$RW_DMG_PATH" \
    -readwrite \
    -noverify \
    -noautoopen | awk 'index($0, "/Volumes/") { print substr($0, index($0, "/Volumes/")); exit }'
)"

if [[ -z "$MOUNT_PATH" || ! -d "$MOUNT_PATH" ]]; then
  echo "Failed to mount writable DMG" >&2
  exit 1
fi

style_dmg_window
verify_dmg_root_contents "$MOUNT_PATH"

hdiutil detach "$MOUNT_PATH" -quiet
MOUNT_PATH=""

hdiutil convert "$RW_DMG_PATH" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_PATH" \
  -quiet

rm -f "$RW_DMG_PATH"

echo "==> Verifying DMG"
hdiutil verify "$DMG_PATH"

echo
echo "DMG created:"
echo "$DMG_PATH"
