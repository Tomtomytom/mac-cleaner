#!/bin/bash
# Builds "Mac Cleaner.app" into ./build. Pass --install to copy it into /Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
[ -f Resources/AppIcon.icns ] || swift scripts/make_icon.swift Resources

APP="build/Mac Cleaner.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/MacCleaner" "$APP/Contents/MacOS/MacCleaner"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "✓ $APP"

if [ "${1:-}" = "--install" ]; then
    # Remove the app installed under its previous name, if any.
    rm -rf "/Applications/Clean Toco.app"
    rm -rf "/Applications/Mac Cleaner.app"
    cp -R "$APP" /Applications/
    echo "✓ installed in /Applications"
fi
