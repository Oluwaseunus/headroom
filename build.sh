#!/bin/zsh
set -eu
cd -- "${0:A:h}"
APP="$PWD/Menu Bar Toggle.app"
BUILD="$PWD/.build"
mkdir -p "$APP/Contents/MacOS" "$BUILD/module-cache"
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun swiftc -O -warnings-as-errors -sdk "$SDK" -target arm64-apple-macosx15.0 \
  -module-cache-path "$BUILD/module-cache" \
  Source/Preferences.swift Source/SelfTests.swift Source/main.swift \
  -o "$APP/Contents/MacOS/MenuBarToggle"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MenuBarToggle</string>
<key>CFBundleIdentifier</key><string>love.oluwaseun.MenuBarToggle</string>
<key>CFBundleName</key><string>Menu Bar Toggle</string>
<key>CFBundleDisplayName</key><string>Menu Bar Toggle</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/MenuBarToggle" --self-test
echo "Built $APP"
