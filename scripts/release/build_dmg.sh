#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
PROJECT_PATH="$PROJECT_ROOT/Framwise.xcodeproj"
SCHEME="Framwise"
CONFIGURATION="Release"
BUILD_DIR="$PROJECT_ROOT/build"
RELEASE_DIR="$PROJECT_ROOT/build/release"
ARCHIVE_PATH="$RELEASE_DIR/Framwise.xcarchive"
EXPORT_DIR="$RELEASE_DIR/export"
TEMPLATE_PATH="$PROJECT_ROOT/scripts/release/export-options-developer-id.plist.template"
EXPORT_OPTIONS_PATH="$RELEASE_DIR/export-options-developer-id.plist"
ENTITLEMENTS_PATH="$RELEASE_DIR/exported-entitlements.plist"

fail() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

require_env() {
    local name="$1"
    if [[ -z "${!name:-}" ]]; then
        fail "$name is required. Example: $name=... scripts/release/build_dmg.sh"
    fi
}

require_tool() {
    command -v "$1" >/dev/null 2>&1 || fail "$1 is required but was not found on PATH"
}

require_safe_artifact_component() {
    local name="$1"
    local value="$2"

    [[ "$value" =~ ^[A-Za-z0-9._-]+$ ]] || fail "$name must contain only letters, numbers, dots, underscores, or hyphens: $value"
}

validate_release_inputs() {
    [[ "$FRAMWISE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || fail "FRAMWISE_TEAM_ID must be a 10-character Apple Developer Team ID"

    if [[ "$FRAMWISE_NOTARY_PROFILE" == *$'\n'* || "$FRAMWISE_NOTARY_PROFILE" == *$'\r'* ]]; then
        fail "FRAMWISE_NOTARY_PROFILE must be a single-line keychain profile name"
    fi
}

prepare_release_dir() {
    local expected="$PROJECT_ROOT/build/release"

    [[ -n "$RELEASE_DIR" ]] || fail "Release directory resolved to an empty path"
    [[ "$RELEASE_DIR" == "$expected" ]] || fail "Refusing to clean unexpected release directory: $RELEASE_DIR"

    if [[ -L "$BUILD_DIR" ]]; then
        fail "Refusing to use symlinked build directory: $BUILD_DIR"
    fi

    if [[ -e "$BUILD_DIR" && ! -d "$BUILD_DIR" ]]; then
        fail "Build path exists but is not a directory: $BUILD_DIR"
    fi

    if [[ -L "$RELEASE_DIR" ]]; then
        fail "Refusing to clean symlinked release directory: $RELEASE_DIR"
    fi

    if [[ -e "$RELEASE_DIR" && ! -d "$RELEASE_DIR" ]]; then
        fail "Release path exists but is not a directory: $RELEASE_DIR"
    fi

    rm -rf "$RELEASE_DIR"
    mkdir -p "$RELEASE_DIR" "$EXPORT_DIR"
}

build_setting() {
    local key="$1"
    xcodebuild \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -showBuildSettings \
        DEVELOPMENT_TEAM="$FRAMWISE_TEAM_ID" \
        2>/dev/null |
        awk -F '= ' -v setting="$key" '$1 ~ "^[[:space:]]*" setting "[[:space:]]*$" { print $2; exit }'
}

plist_value() {
    local plist_path="$1"
    local key="$2"
    /usr/libexec/PlistBuddy -c "Print :$key" "$plist_path" 2>/dev/null
}

assert_not_sandboxed() {
    local app_path="$1"
    local entitlements_path="$2"
    local sandbox_value

    codesign -d --entitlements :- "$app_path" 2>/dev/null |
        awk '/^<\?xml/ { found = 1 } found { print }' > "$entitlements_path"

    if [[ ! -s "$entitlements_path" ]]; then
        printf 'No signed entitlements found; continuing non-sandbox release.\n'
        return
    fi

    sandbox_value="$(plist_value "$entitlements_path" "com.apple.security.app-sandbox" || true)"
    if [[ "$sandbox_value" == "true" || "$sandbox_value" == "1" ]]; then
        fail "Exported app is sandboxed, but Framwise does not implement security-scoped bookmarks. Disable sandbox for DMG release or implement bookmark support first."
    fi

    printf 'Confirmed exported app is not sandboxed.\n'
}

assert_universal_macos_app() {
    local executable_path="$1"
    local archs

    [[ -x "$executable_path" ]] || fail "Exported app executable not found or not executable: $executable_path"

    archs="$(lipo -archs "$executable_path" 2>/dev/null)" || fail "Could not inspect exported app architectures"
    [[ " $archs " == *" arm64 "* ]] || fail "Exported app is missing arm64 slice. Found architectures: ${archs:-<none>}"
    [[ " $archs " == *" x86_64 "* ]] || fail "Exported app is missing x86_64 slice. Found architectures: ${archs:-<none>}"

    printf 'Confirmed exported app executable is universal: %s\n' "$archs"
}

assert_no_local_dynamic_library_dependencies() {
    local executable_path="$1"
    local local_dependency

    local_dependency="$(
        otool -L "$executable_path" |
            awk 'NR > 1 { print $1 }' |
            grep -E '^(/Users/|/opt/homebrew/|/usr/local/)' || true
    )"

    if [[ -n "$local_dependency" ]]; then
        fail "Exported app links against a local developer-machine dependency: $local_dependency"
    fi

    printf 'Confirmed exported app has no local Homebrew or user-path dynamic library dependencies.\n'
}

plist_escape() {
    printf '%s' "$1" |
        sed \
            -e 's/&/\&amp;/g' \
            -e 's/</\&lt;/g' \
            -e 's/>/\&gt;/g' \
            -e 's/"/\&quot;/g' \
            -e "s/'/\&apos;/g"
}

require_env FRAMWISE_TEAM_ID
require_env FRAMWISE_NOTARY_PROFILE
validate_release_inputs
require_tool xcodebuild
require_tool xcrun
require_tool hdiutil
require_tool codesign
require_tool lipo
require_tool otool
require_tool spctl
require_tool shasum

[[ -d "$PROJECT_PATH" ]] || fail "Xcode project not found at $PROJECT_PATH"
[[ -f "$TEMPLATE_PATH" ]] || fail "Export options template not found at $TEMPLATE_PATH"

VERSION="$(build_setting MARKETING_VERSION)"
BUILD_NUMBER="$(build_setting CURRENT_PROJECT_VERSION)"
DEPLOYMENT_TARGET="$(build_setting MACOSX_DEPLOYMENT_TARGET)"
[[ -n "$VERSION" ]] || fail "Could not resolve MARKETING_VERSION from Xcode build settings"
[[ -n "$BUILD_NUMBER" ]] || fail "Could not resolve CURRENT_PROJECT_VERSION from Xcode build settings"
[[ -n "$DEPLOYMENT_TARGET" ]] || fail "Could not resolve MACOSX_DEPLOYMENT_TARGET from Xcode build settings"
require_safe_artifact_component MARKETING_VERSION "$VERSION"
require_safe_artifact_component CURRENT_PROJECT_VERSION "$BUILD_NUMBER"

DMG_PATH="$RELEASE_DIR/Framwise-$VERSION-$BUILD_NUMBER.dmg"
TMP_DMG_PATH="$RELEASE_DIR/Framwise-$VERSION-$BUILD_NUMBER.unsigned.dmg"

printf 'Preparing release directory: %s\n' "$RELEASE_DIR"
prepare_release_dir

TEAM_ID_ESCAPED="$(plist_escape "$FRAMWISE_TEAM_ID")"
sed "s/__TEAM_ID__/$TEAM_ID_ESCAPED/g" "$TEMPLATE_PATH" > "$EXPORT_OPTIONS_PATH"

printf 'Archiving %s %s (%s)...\n' "$SCHEME" "$VERSION" "$BUILD_NUMBER"
xcodebuild archive \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$ARCHIVE_PATH" \
    DEVELOPMENT_TEAM="$FRAMWISE_TEAM_ID" \
    CODE_SIGN_STYLE=Automatic \
    ENABLE_HARDENED_RUNTIME=YES \
    VALIDATE_PRODUCT=YES

printf 'Exporting Developer ID app...\n'
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PATH"

APP_PATH="$EXPORT_DIR/Framwise.app"
[[ -d "$APP_PATH" ]] || fail "Exported app not found at $APP_PATH"
APP_INFO_PLIST="$APP_PATH/Contents/Info.plist"
[[ -f "$APP_INFO_PLIST" ]] || fail "Exported app Info.plist not found at $APP_INFO_PLIST"

EXPORTED_VERSION="$(plist_value "$APP_INFO_PLIST" CFBundleShortVersionString)"
EXPORTED_BUILD_NUMBER="$(plist_value "$APP_INFO_PLIST" CFBundleVersion)"
EXPORTED_EXECUTABLE_NAME="$(plist_value "$APP_INFO_PLIST" CFBundleExecutable)"
EXPORTED_MINIMUM_SYSTEM_VERSION="$(plist_value "$APP_INFO_PLIST" LSMinimumSystemVersion)"
[[ "$EXPORTED_VERSION" == "$VERSION" ]] || fail "Exported app version mismatch: expected $VERSION, found ${EXPORTED_VERSION:-<empty>}"
[[ "$EXPORTED_BUILD_NUMBER" == "$BUILD_NUMBER" ]] || fail "Exported app build mismatch: expected $BUILD_NUMBER, found ${EXPORTED_BUILD_NUMBER:-<empty>}"
[[ -n "$EXPORTED_EXECUTABLE_NAME" ]] || fail "Exported app executable name is missing from Info.plist"
[[ "$EXPORTED_MINIMUM_SYSTEM_VERSION" == "$DEPLOYMENT_TARGET" ]] || fail "Exported app minimum system version mismatch: expected $DEPLOYMENT_TARGET, found ${EXPORTED_MINIMUM_SYSTEM_VERSION:-<empty>}"

printf 'Verifying exported app architectures...\n'
APP_EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/$EXPORTED_EXECUTABLE_NAME"
assert_universal_macos_app "$APP_EXECUTABLE_PATH"

printf 'Verifying exported app dynamic library dependencies...\n'
assert_no_local_dynamic_library_dependencies "$APP_EXECUTABLE_PATH"

printf 'Verifying exported app is not sandboxed...\n'
assert_not_sandboxed "$APP_PATH" "$ENTITLEMENTS_PATH"

printf 'Verifying exported app signature...\n'
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

printf 'Creating DMG...\n'
hdiutil create \
    -volname "Framwise" \
    -srcfolder "$APP_PATH" \
    -ov \
    -format UDZO \
    "$TMP_DMG_PATH"

mv "$TMP_DMG_PATH" "$DMG_PATH"

printf 'Submitting DMG for notarization with profile %s...\n' "$FRAMWISE_NOTARY_PROFILE"
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$FRAMWISE_NOTARY_PROFILE" \
    --wait

printf 'Stapling notarization ticket...\n'
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

printf 'Verifying DMG Gatekeeper assessment...\n'
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"

printf 'Release artifact ready:\n'
printf '  %s\n' "$DMG_PATH"
printf 'SHA256:\n'
shasum -a 256 "$DMG_PATH"
