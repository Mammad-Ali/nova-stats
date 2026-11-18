#!/bin/bash
# builds a release copy and puts it in /Applications
set -euo pipefail
cd "$(dirname "$0")/.."

xcodebuild -project NovaStats.xcodeproj -scheme NovaStats -configuration Release \
  -derivedDataPath build/dd build -quiet

app="build/dd/Build/Products/Release/Nova Stats.app"
dest="/Applications/Nova Stats.app"

# widgets only load from a sandboxed extension, don't install a build without one
if ! codesign -d --entitlements - --xml "$app/Contents/PlugIns/NovaStatsWidgets.appex" 2>/dev/null | grep -q app-sandbox; then
  echo "widget extension isn't sandboxed, not installing" >&2
  exit 1
fi

pkill -x "Nova Stats" 2>/dev/null && sleep 1 || true
rm -rf "$dest"
ditto "$app" "$dest"
xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true
open "$dest"
echo "installed $dest"
