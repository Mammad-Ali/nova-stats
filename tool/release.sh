#!/bin/bash
# makes Nova-Stats.dmg and publishes it as a github release: tool/release.sh 1.0.0
set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:?usage: tool/release.sh 1.0.0}"
gh="$(command -v gh || echo "$HOME/.local/bin/gh")"

if [ -n "$(git status --porcelain)" ]; then
  echo "commit your changes first" >&2
  exit 1
fi
if ! grep -q "MARKETING_VERSION = $version;" NovaStats.xcodeproj/project.pbxproj; then
  echo "the project's version isn't $version" >&2
  exit 1
fi

rm -rf build/release
xcodebuild -project NovaStats.xcodeproj -scheme NovaStats -configuration Release \
  -derivedDataPath build/dd build -quiet

app="build/dd/Build/Products/Release/Nova Stats.app"
if ! codesign -d --entitlements - --xml "$app/Contents/PlugIns/NovaStatsWidgets.appex" 2>/dev/null | grep -q app-sandbox; then
  echo "widget extension isn't sandboxed, not releasing" >&2
  exit 1
fi

# the dmg opens to the app next to a link to Applications
mkdir -p build/release/dmg
ditto "$app" "build/release/dmg/Nova Stats.app"
ln -s /Applications build/release/dmg/Applications
hdiutil create -volname "Nova Stats" -srcfolder build/release/dmg -ov -format UDZO build/release/Nova-Stats.dmg -quiet

git tag "v$version"
git push origin "v$version"
"$gh" release create "v$version" build/release/Nova-Stats.dmg \
  --title "Nova Stats $version" --notes-file .github/release-notes.md
echo "released v$version"
