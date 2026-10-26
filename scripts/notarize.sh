#!/bin/bash
source "$(dirname "$0")/lib.sh"

require NOTARY_PROFILE SPARKLE_ACCOUNT SITE_URL
sparkle=macos/.build/artifacts/sparkle/Sparkle/bin

if [ "$SIGN_ID" = "-" ]; then
  echo "Set SIGN_ID in .env, for example: SIGN_ID=Developer ID Application: Your Name (TEAMID)"
  exit 1
fi

submit() {
  local result
  result=$(xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)
  echo "$result"
  if ! echo "$result" | grep -q "status: Accepted"; then
    echo "Notarization of $1 was not accepted"
    exit 1
  fi
}

release=$(version)
folder=$(release_dir "$release")
image=$folder/Rackpulse-$release.dmg

scripts/build.sh
codesign --verify --deep --strict "$APP"

rm -f dist/Rackpulse.zip
ditto -c -k --keepParent "$APP" dist/Rackpulse.zip
submit dist/Rackpulse.zip
xcrun stapler staple "$APP"
rm -f dist/Rackpulse.zip

scripts/dmg.sh
codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
submit "$DMG"
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"

mkdir -p "$folder"
mv "$DMG" "$image"
awk -v head="## $release" '$0 == head { found = 1; next } found && /^## / { exit } found' CHANGELOG.md | sed '/./,$!d' >"$folder/Rackpulse-$release.md"
if [ ! -s "$folder/Rackpulse-$release.md" ]; then
  echo "CHANGELOG.md has no section for $release. Add one and run make notarize again"
  exit 1
fi
feed_view
"$sparkle/generate_appcast" --account "$SPARKLE_ACCOUNT" --embed-release-notes --download-url-prefix "$SITE_URL/download/" -o dist/appcast.xml "$FEED"
for delta in "$FEED/Rackpulse$release-"*.delta; do
  if [ -f "$delta" ] && [ ! -f "$folder/$(basename "$delta")" ]; then cp "$delta" "$folder/"; fi
done
rm -rf "$FEED"
echo "Notarized $image"
echo "Update feed written to dist/appcast.xml"
