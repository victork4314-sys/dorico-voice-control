#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "The macOS app and DMG must be built on macOS."
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
DIST="$ROOT/dist"
APP="$DIST/Dorico Voice Control.app"
CONTENTS="$APP/Contents"

rm -rf "$DIST" "$ROOT/.build-arm64" "$ROOT/.build-x86_64"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

swift test
bash scripts/verify-source-safety.sh
swift build -c release --product DoricoVoiceControl --arch arm64 --scratch-path "$ROOT/.build-arm64"
swift build -c release --product DoricoVoiceControl --arch x86_64 --scratch-path "$ROOT/.build-x86_64"
lipo -create \
  "$ROOT/.build-arm64/arm64-apple-macosx/release/DoricoVoiceControl" \
  "$ROOT/.build-x86_64/x86_64-apple-macosx/release/DoricoVoiceControl" \
  -output "$CONTENTS/MacOS/DoricoVoiceControl"
chmod +x "$CONTENTS/MacOS/DoricoVoiceControl"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleDisplayName</key><string>Dorico Voice Control</string>
  <key>CFBundleExecutable</key><string>DoricoVoiceControl</string>
  <key>CFBundleIdentifier</key><string>org.figureloom.DoricoVoiceControl</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Dorico Voice Control</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Dorico Voice Control uses the microphone only while listening to recognize spoken Dorico commands.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Dorico Voice Control uses macOS Speech Recognition to turn your speech into Dorico command previews.</string>
</dict>
</plist>
PLIST

plutil -lint "$CONTENTS/Info.plist"
codesign --force --deep --sign - "$APP"
bash scripts/verify-app.sh "$APP"

ZIP="$DIST/Dorico-Voice-Control-macOS-Universal.zip"
DMG="$DIST/Dorico-Voice-Control-macOS-Universal.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

ZIP_CHECK="$DIST/zip-check"
mkdir -p "$ZIP_CHECK"
ditto -x -k "$ZIP" "$ZIP_CHECK"
bash scripts/verify-app.sh "$ZIP_CHECK/Dorico Voice Control.app"
rm -rf "$ZIP_CHECK"

DMG_ROOT="$DIST/dmg-root"
mkdir -p "$DMG_ROOT"
cp -R "$APP" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create -volname "Dorico Voice Control" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG"
rm -rf "$DMG_ROOT"

MOUNT="$DIST/mounted-dmg"
mkdir -p "$MOUNT"
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT"
bash scripts/verify-app.sh "$MOUNT/Dorico Voice Control.app"
hdiutil detach "$MOUNT"
rmdir "$MOUNT"

(
  cd "$DIST"
  shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" > SHA256SUMS.txt
)

echo "Built $APP"
echo "Built $ZIP"
echo "Built $DMG"
