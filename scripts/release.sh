#!/usr/bin/env bash
# Builds an ad-hoc signed, universal Kapture.app and packages it as dist/Kapture-<version>.dmg.
# It never publishes; upload the DMG with `gh release create`.
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: working tree is dirty; commit or stash first" >&2
  exit 1
fi

version=$(awk -F'"' '/MARKETING_VERSION:/ {print $2}' project.yml)
if [[ -z "$version" ]]; then
  echo "error: MARKETING_VERSION not found in project.yml" >&2
  exit 1
fi
echo "==> Kapture $version"

xcodegen generate
swift test

rm -rf build dist
xcodebuild -project Kapture.xcodeproj -scheme Kapture -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  build | tail -n 1

app=build/Build/Products/Release/Kapture.app
codesign --verify --deep --strict "$app"

archs=$(lipo -archs "$app/Contents/MacOS/Kapture")
if [[ "$archs" != *arm64* || "$archs" != *x86_64* ]]; then
  echo "error: expected a universal binary, got: $archs" >&2
  exit 1
fi

built=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
if [[ "$built" != "$version" ]]; then
  echo "error: app reports version $built, project.yml says $version" >&2
  exit 1
fi

staging=build/dmg
mkdir -p "$staging" dist
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"

dmg="dist/Kapture-$version.dmg"
hdiutil create -volname "Kapture $version" -srcfolder "$staging" -format UDZO -ov "$dmg" >/dev/null

echo "==> $dmg"
shasum -a 256 "$dmg"
