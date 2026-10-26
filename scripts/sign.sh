#!/bin/bash
source "$(dirname "$0")/lib.sh"

flags=""
if [ "$SIGN_ID" != "-" ] && [ -z "${DEV_BUILD:-}" ]; then flags="--options runtime --timestamp"; fi

sign() {
  codesign --force $flags --sign "$SIGN_ID" "$@"
}

sparkle=$APP/Contents/Frameworks/Sparkle.framework

if [ -d "$sparkle" ]; then
  for part in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do
    sign --preserve-metadata=entitlements "$sparkle/Versions/B/$part"
  done
  sign "$sparkle"
fi
entitlements=$ENTITLEMENTS
if [ -n "${DEV_BUILD:-}" ]; then entitlements=macos/Rackpulse-dev.entitlements; fi
sign --entitlements "$entitlements" "$APP"
