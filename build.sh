#!/bin/zsh
set -eu
cd -- "${0:A:h}"
APP="$PWD/Headroom.app"
BUILD="$PWD/.build"
SETTINGS_APP="$APP/Contents/Helpers/Headroom Settings.app"
mkdir -p "$APP/Contents/MacOS" "$SETTINGS_APP/Contents/MacOS" "$BUILD/module-cache"
SDK=$(xcrun --sdk macosx --show-sdk-path)
SIGNING_IDENTITY="${MENU_BAR_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  # Prefer the one available Developer ID identity; never silently fall back
  # to ad-hoc signing, which invalidates Accessibility grants after rebuilds.
  IDENTITIES=$(security find-identity -v -p codesigning)
  SIGNING_IDENTITY=$(print -r -- "$IDENTITIES" | awk '/"Developer ID Application:/ { print $2 }')
fi
if [[ -z "$SIGNING_IDENTITY" || "$SIGNING_IDENTITY" == *$'\n'* || "$SIGNING_IDENTITY" == "-" ]]; then
  print -u2 'Set MENU_BAR_SIGNING_IDENTITY to a valid code-signing certificate name or SHA-1. A stable identity is required for Accessibility permission continuity.'
  exit 1
fi
xcrun swiftc -O -warnings-as-errors -sdk "$SDK" -target arm64-apple-macosx15.0 \
  -module-cache-path "$BUILD/module-cache" \
  Source/Preferences.swift Source/AppRules.swift Source/FullscreenMonitor.swift Source/SettingsBridge.swift Source/SelfTests.swift Source/main.swift \
  -o "$APP/Contents/MacOS/MenuBarToggle"
xcrun swiftc -O -warnings-as-errors -sdk "$SDK" -target arm64-apple-macosx15.0 \
  -module-cache-path "$BUILD/module-cache" \
  Source/Preferences.swift Source/AppRules.swift Source/SettingsBridge.swift Source/DisplayInfo.swift Source/SettingsWindow.swift Source/SettingsMain.swift \
  -o "$SETTINGS_APP/Contents/MacOS/MenuBarToggleSettings"
cat > "$SETTINGS_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MenuBarToggleSettings</string>
<key>CFBundleIdentifier</key><string>love.oluwaseun.MenuBarToggle.Settings</string>
<key>CFBundleName</key><string>Headroom</string>
<key>CFBundleDisplayName</key><string>Headroom</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.4.0</string>
<key>CFBundleVersion</key><string>5</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --timestamp=none --sign "$SIGNING_IDENTITY" "$SETTINGS_APP"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MenuBarToggle</string>
<key>CFBundleIdentifier</key><string>love.oluwaseun.MenuBarToggle</string>
<key>CFBundleName</key><string>Headroom</string>
<key>CFBundleDisplayName</key><string>Headroom</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.4.0</string>
<key>CFBundleVersion</key><string>5</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --timestamp=none --sign "$SIGNING_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
"$APP/Contents/MacOS/MenuBarToggle" --self-test
echo "Built $APP"
