#!/usr/bin/env bash
set -euo pipefail

APP="${1:?Pass the .app path}"
PLIST="$APP/Contents/Info.plist"
EXECUTABLE="$APP/Contents/MacOS/DoricoVoiceControl"

[[ -f "$PLIST" ]]
[[ -x "$EXECUTABLE" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")" == "org.figureloom.DoricoVoiceControl" ]]
/usr/libexec/PlistBuddy -c 'Print :NSMicrophoneUsageDescription' "$PLIST" | grep -q 'recognize spoken Dorico commands'
/usr/libexec/PlistBuddy -c 'Print :NSSpeechRecognitionUsageDescription' "$PLIST" | grep -q 'turn your speech into Dorico command previews'
lipo -info "$EXECUTABLE" | grep -q 'arm64'
lipo -info "$EXECUTABLE" | grep -q 'x86_64'
codesign --verify --deep --strict "$APP"

echo "App bundle verified: $APP"
